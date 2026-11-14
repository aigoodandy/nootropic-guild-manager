--[[
    Nootropic Guild Manager - Recruitment service
    Runs /who searches for players without a guild (never anyone in one), remembers who you've contacted,
    fills in per-class whisper templates, and pops up an Invite prompt (see
    UI/InvitePrompt.lua) when a whispered player replies with one of your keywords.

    Saved per guild in guild.recruit:
      default    = "whisper used when a class has no message of its own"
      templates  = { [CLASSFILE] = "..." }
      keywords   = { "invite", ... }          -- up to 6
      autoInvite = true                       -- invite on a keyword reply
      inviteMode = "confirm"                  -- always: Forever only allows invites from a click
      query      = { min, max, class, zone, step, name, hideContacted,
                     zoneAuto, levelAuto }       -- *Auto: follow the player (see ApplyAutoQuery)
      people     = { ["Name-Realm"] = { level, classFile, className, zone, guild,
                     found, seen, whispered, replied, reply, invited, joined } }
      dnwEnabled = true                       -- watch replies for Do Not Whisper words
      dnwWords   = { "dnw", "leave me alone", ... }   -- up to 6
      (the Do Not Whisper list itself is shared: sync records DN:<player>)
      (statuses are shared for 14 days: sync records RS:<player>, see Contact;
       while one is, nobody in the guild can queue another whisper to that player)
]]
local _, ns = ...
local D = ns.Data
local RC = {}
ns.Recruit = RC

local WHO_TIMEOUT = 8          -- seconds to wait for /who results
-- /who limits, kept well inside what the server tolerates from a person typing:
RC.WHO_COOLDOWN = 15           -- seconds between searches
RC.WHO_WINDOW = 300            -- rolling window (seconds)...
RC.WHO_MAX_PER_WINDOW = 12     -- ...and how many searches it allows
local PRUNE_AFTER = 30 * 86400 -- forget uncontacted players after 30 days
-- After anyone in the guild whispers a player, nobody can queue another
-- recruitment whisper to them for this long (the shared status lasts as long).
RC.RECONTACT_DAYS = 14

RC.searching = false
RC.history = {} -- GetTime() of recent searches
RC.last = nil -- { query, shown, total, unguilded, new }

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
function RC:Settings()
    local g = ns.DB:Guild()
    if not g then return nil end
    local r = g.recruit
    if not r then
        r = {}
        g.recruit = r
    end

    if r.default == nil then r.default = D.DEFAULT_WHISPER end
    for _, old in ipairs(D.OLD_DEFAULT_WHISPERS) do
        if r.default == old then r.default = D.DEFAULT_WHISPER end
    end
    if not r.keywords then
        r.keywords = {}
        for i, k in ipairs(D.DEFAULT_KEYWORDS) do r.keywords[i] = k end
        r.keywordsYeahAdded = true
    end
    if r.autoInvite == nil then r.autoInvite = true end
    r.inviteMode = "confirm" -- WoW: Forever blocks addon invites; the Invite prompt runs /ginvite on your click
    r.people = r.people or {}
    r.query = r.query or { min = 1, max = 60, step = false }
    r.query.guildOn, r.query.guild = nil, nil -- 2.0: guild search removed
    r.query.name = r.query.name or ""
    if r.dnwEnabled == nil then r.dnwEnabled = true end
    -- 2.6.2: click-only whispering used to be saved for good after a single
    -- blocked whisper; it now lasts the session (RC.clickOnly)
    r.whisperMode = nil
    ns.Messages:Migrate(r)
    if not r.dnwWords then
        r.dnwWords = {}
        for i, w in ipairs(D.DEFAULT_DNW_WORDS) do r.dnwWords[i] = w end
        r.dnwNoAdded = true
    end
    -- 2.1.9: "yeah" joined the invite keywords (the built-in messages ask a
    -- question now); add it once, in a free box
    if not r.keywordsYeahAdded then
        r.keywordsYeahAdded = true
        local has, free = false, nil
        for i = 1, D.MAX_KEYWORDS do
            local w = ns.Trim(r.keywords[i] or ""):lower()
            if w == "yeah" then has = true end
            if w == "" and not free then free = i end
        end
        if not has and free then r.keywords[free] = "yeah" end
    end
    -- 2.1.3: "no" joined the defaults; add it once (in a free box), so
    -- removing it later sticks
    if not r.dnwNoAdded then
        r.dnwNoAdded = true
        local has, free = false, nil
        for i = 1, D.MAX_KEYWORDS do
            local w = ns.Trim(r.dnwWords[i] or ""):lower()
            if w == "no" then has = true end
            if w == "" and not free then free = i end
        end
        if not has and free then r.dnwWords[free] = "no" end
    end
    if not self.pruned then
        self.pruned = true
        local cutoff = ns.DB:Now() - PRUNE_AFTER
        for full, p in pairs(r.people) do
            -- 1.x guild searches could list players in other guilds: drop the ones never contacted
            if not p.whispered and not p.invited and ((p.seen or 0) < cutoff or p.guild) then r.people[full] = nil end
        end
    end
    return r
end

function RC:MaxLevel()
    return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
end

local function Changed()
    ns:Fire("RECRUITS_CHANGED")
end

------------------------------------------------------------------------
-- People
------------------------------------------------------------------------
function RC:Get(full)
    local r = self:Settings()
    return r and r.people[full]
end

------------------------------------------------------------------------
-- Shared status: whoever whispers, hears back from, or invites a player
-- shares it with the guild (sync record RS:<player> = "whispered;replied;
-- invited;reply", times or empty). Records expire after 14 days.
------------------------------------------------------------------------
local function RSKey(full) return "RS:" .. full end

-- { w, r, i, reply, by, t } shared by the guild, or nil.
function RC:Shared(full)
    if not full then return nil end
    local rec = ns.Sync:Get(RSKey(full))
    if not rec or rec.v == "" then return nil end
    local def = ns.Sync.TYPES.RS
    if rec.t < ns.DB:Now() - def.ttl then return nil end
    local w, r, i, reply = rec.v:match("^(%d*);(%d*);(%d*);(.*)$")
    if not w then return nil end
    return { w = tonumber(w), r = tonumber(r), i = tonumber(i), reply = reply ~= "" and reply or nil, by = rec.a, t = rec.t }
end

local function Later(a, b)
    if a and b then return math.max(a, b) end
    return a or b
end

-- Shares what we know about `full` (merged with what the guild knows).
-- `clear` = { whispered = true } drops a field (a whisper the game refused).
function RC:ShareStatus(full, clear)
    if not (full and ns.DB:Guild() and IsInGuild()) then return end
    local p = self:Get(full) or {}
    local sh = self:Shared(full) or {}
    clear = clear or {}
    local w = not clear.whispered and Later(p.whispered, sh.w) or nil
    local r = Later(p.replied, sh.r)
    local i = not clear.invited and Later(p.invited, sh.i) or nil
    local reply = (p.replied and (not sh.r or p.replied >= sh.r)) and p.reply or sh.reply
    reply = ns.Sync.Clean(reply or ""):sub(1, 80)
    local v = ("%s;%s;%s;%s"):format(w or "", r or "", i or "", reply)
    if v == ";;;" then
        if sh.t then ns.Sync:Set(RSKey(full), "") end -- nothing left to share
        return
    end
    ns.Sync:Set(RSKey(full), v)
end

-- What the guild knows about contacting `p`: { whispered, replied, invited,
-- reply, by } where `by` is set when someone else contacted them and you didn't.
function RC:Contact(p)
    local sh = self:Shared(p.full)
    local c = { whispered = p.whispered, replied = p.replied, invited = p.invited, reply = p.reply }
    if sh then
        c.whispered = Later(c.whispered, sh.w)
        c.replied = Later(c.replied, sh.r)
        c.invited = Later(c.invited, sh.i)
        if sh.r and (not p.replied or sh.r > p.replied) then c.reply = sh.reply end
        if sh.by and sh.by ~= ns.PlayerFullName() and not p.whispered and not p.invited then c.by = sh.by end
    end
    return c
end

-- joined > dnw > invited > replied > whispered > new
function RC:Status(p)
    if p.joined then return "joined" end
    if self:IsDNW(p.full) then return "dnw" end
    local c = self:Contact(p)
    if c.invited then return "invited" end
    if c.replied then return "replied" end
    if c.whispered then return "whispered" end
    return "new"
end

-- Server time until which nobody may queue another whisper to `p` (someone
-- in the guild whispered them less than RECONTACT_DAYS ago), or nil.
function RC:LockedUntil(p)
    local c = self:Contact(p)
    if not c.whispered then return nil end
    local untilT = c.whispered + self.RECONTACT_DAYS * 86400
    if untilT > ns.DB:Now() then return untilT end
end

function RC:IsContacted(p)
    local c = self:Contact(p)
    return (c.whispered or c.invited or p.joined or self:IsDNW(p.full)) and true or false
end

-- opts: { hideContacted = bool, text = "filter", name = "part of a name" }
function RC:List(opts)
    opts = opts or {}
    local r = self:Settings()
    local out = {}
    if not r then return out end
    local text = opts.text and opts.text:lower() or ""
    local name = opts.name and ns.Trim(opts.name):lower() or ""
    for full, p in pairs(r.people) do
        p.full = full
        local contacted = self:IsContacted(p)
        if not (opts.hideContacted and contacted)
            and (name == "" or full:lower():find(name, 1, true))
            and (text == "" or (full:lower() .. " " .. (p.className or ""):lower() .. " " .. (p.zone or ""):lower()):find(text, 1, true)) then
            p.full = full
            p.short = ns.ShortName(full)
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b)
        if (a.seen or 0) ~= (b.seen or 0) then return (a.seen or 0) > (b.seen or 0) end
        return a.full < b.full
    end)
    return out
end

function RC:Remove(full)
    local r = self:Settings()
    if r and r.people[full] then
        r.people[full] = nil
        Changed()
    end
end

function RC:ClearUncontacted()
    local r = self:Settings()
    if not r then return end
    for full, p in pairs(r.people) do
        p.full = full
        if not self:IsContacted(p) then r.people[full] = nil end
    end
    Changed()
end

------------------------------------------------------------------------
-- /who searching
------------------------------------------------------------------------
function RC:BuildQuery(q)
    local parts = {}
    local lo = math.max(1, tonumber(q.min) or 1)
    local hi = math.max(lo, tonumber(q.max) or lo)
    local name = ns.Trim(q.name)
    if name ~= "" then parts[#parts + 1] = ('n-"%s"'):format((name:gsub('[%c"]', ""))) end
    parts[#parts + 1] = ("%d-%d"):format(lo, hi)
    if q.class then parts[#parts + 1] = ('c-"%s"'):format(D:ClassName(q.class)) end
    local zone = ns.Trim(q.zone)
    if zone ~= "" then parts[#parts + 1] = ('z-"%s"'):format((zone:gsub('[%c"]', ""))) end
    return table.concat(parts, " ")
end

-- Seconds until the next search is allowed (0 = now).
function RC:CooldownRemaining()
    local now = GetTime()
    -- forget searches that have left the rolling window
    for i = #self.history, 1, -1 do
        if now - self.history[i] >= self.WHO_WINDOW then table.remove(self.history, i) end
    end
    local wait = 0
    local last = self.history[#self.history]
    if last then wait = math.max(wait, self.WHO_COOLDOWN - (now - last)) end
    if #self.history >= self.WHO_MAX_PER_WINDOW then
        wait = math.max(wait, self.WHO_WINDOW - (now - self.history[1]))
    end
    return math.max(0, wait)
end

-- Zone and levels follow the player unless they typed their own: the zone
-- you're in, and 3 levels below you to 2 above. Clearing a box (zoneAuto /
-- levelAuto true) switches it back. Step levels keeps the range it reached.
function RC:ApplyAutoQuery()
    local r = self:Settings()
    if not r then return end
    local q = r.query
    if q.zoneAuto ~= false then
        local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
        if zone and zone ~= "" then q.zone = zone end
    end
    if q.levelAuto ~= false and not q.step then
        local level = UnitLevel and UnitLevel("player") or 1
        q.min = math.max(1, level - 3)
        q.max = math.max(q.min, math.min(self:MaxLevel(), level + 2))
    end
end

-- Checks the limits and records a search about to happen. Returns the /who
-- query text, or nil plus a reason. The search itself runs through a secure
-- "/who" button (C_FriendList.SendWho is restricted to Blizzard's own UI).
function RC:BeginSearch()
    local r = self:Settings()
    if not r then return nil, "You are not in a guild." end
    if self.searching then return nil, "Still waiting for the last search." end
    local wait = self:CooldownRemaining()
    if wait > 0 then
        return nil, ("Searching too often could get you flagged for spam. Try again in %d seconds."):format(math.ceil(wait))
    end
    table.insert(self.history, GetTime())
    self:ApplyAutoQuery()
    local text = self:BuildQuery(r.query)
    self.searching = true
    self.token = (self.token or 0) + 1
    local token = self.token
    self.pendingQuery = text
    if C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(true)
    elseif SetWhoToUI then
        SetWhoToUI(1)
    end
    C_Timer.After(WHO_TIMEOUT, function()
        if RC.searching and RC.token == token then
            RC.searching = false
            RC.last = { query = text, timedOut = true }
            Changed()
        end
    end)
    Changed()
    return text
end

-- The slash command line the secure button runs.
function RC:WhoMacro()
    local text, err = self:BeginSearch()
    if not text then
        if err then ns:Print("|cffff2020" .. err .. "|r") end
        return nil
    end
    return ((SLASH_WHO1 or "/who") .. " " .. text):sub(1, 255)
end

-- Direct search, only used where no secure button exists (older clients).
function RC:Search()
    local text, err = self:BeginSearch()
    if not text then return false, err end
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(text)
    elseif SendWho then
        SendWho(text)
    end
    return true
end

-- Gender as "male" / "female" from either API's numbering.
local function ModernSex(v)
    local U = Enum and Enum.UnitSex
    if U and U.Male ~= nil then
        if v == U.Male then return "male" elseif v == U.Female then return "female" end
        return nil
    end
    if v == 0 then return "male" elseif v == 1 then return "female" end
end
local function LegacySex(v)
    if v == 2 then return "male" elseif v == 3 then return "female" end
end

local function ReadWho(i)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local info = C_FriendList.GetWhoInfo(i)
        if info then
            return info.fullName, info.fullGuildName, info.level, info.classStr, info.filename, info.area,
                info.raceStr, ModernSex(info.gender)
        end
    elseif GetWhoInfo then
        local name, guild, level, race, className, zone, classFile, sex = GetWhoInfo(i)
        return name, guild, level, className, classFile, zone, race, LegacySex(sex)
    end
end

RC.ReadWho = ReadWho -- also used by the /who window's invite buttons

function RC:OnWhoResults()
    if not self.searching then return end -- someone else's /who
    self.searching = false
    local r = self:Settings()
    local shown, total
    if C_FriendList and C_FriendList.GetNumWhoResults then
        shown, total = C_FriendList.GetNumWhoResults()
    elseif GetNumWhoResults then
        shown, total = GetNumWhoResults()
    end
    shown = shown or 0
    local matched, new, skipped = 0, 0, 0
    local now = ns.DB:Now()
    -- only players without a guild are ever kept
    for i = 1, shown do
        local name, guild, level, className, classFile, zone, race, sex = ReadWho(i)
        if name and (guild or "") == "" then
            local full = ns.NormalizeName(name)
            if full ~= ns.PlayerFullName() and not ns.Roster.byName[full] then
                if self:IsDNW(full) and not r.people[full] then
                    skipped = skipped + 1 -- asked not to be contacted
                else
                    matched = matched + 1
                    local p = r.people[full]
                    if not p then
                        p = { found = now }
                        r.people[full] = p
                        new = new + 1
                    end
                    p.level, p.classFile, p.className, p.zone, p.seen = level, classFile, className, zone, now
                    p.guild = nil
                    p.race, p.sex = race, sex
                end
            end
        end
    end
    self.last = { query = self.pendingQuery, shown = shown, total = total or shown, unguilded = matched,
        matched = matched, new = new, skipped = skipped }

    -- Step to the next level bracket for the next click
    local q = r.query
    if q.step then
        local size = math.max(1, (q.max or 1) - (q.min or 1) + 1)
        q.min = (q.max or 1) + 1
        if q.min > self:MaxLevel() then q.min = 1 end
        q.max = math.min(self:MaxLevel(), q.min + size - 1)
    end
    Changed()
end

------------------------------------------------------------------------
-- Whispers
------------------------------------------------------------------------
-- Returns the template text and which slot it came from ("DEFAULT" or a class).
-- The message a player gets: text, and the custom message rule that chose it
-- (nil = Default message). Accepts a recruit, or just a class file.
function RC:TemplateFor(p)
    if type(p) ~= "table" then p = { classFile = p } end
    return ns.Messages:Pick(p)
end

function RC:SetDefault(text)
    local r = self:Settings()
    if r then r.default = text end
end

local function GuildTag()
    local guild = GetGuildInfo("player")
    return (guild and guild ~= "") and ("<" .. guild .. ">") or ""
end

local function Fill(template, p, name, guild)
    local out = (template or ""):gsub("%$(%a+)", function(key)
        key = key:lower()
        if key == "name" then return name
        elseif key == "first" then return (ns.SplitName(name))
        elseif key == "class" then return p.className or D:ClassName(p.classFile)
        elseif key == "level" then return tostring(p.level or "")
        elseif key == "guild" then return guild
        elseif key == "race" then return p.race or ""
        elseif key == "zone" then return p.zone or ""
        end
    end)
    return ns.Trim((out:gsub("[\r\n]+", " ")))
end

-- Cuts `text` to `max` bytes at the last space, never inside a word or a
-- multi-byte letter.
local function CutAtWord(text, max)
    if #text <= max then return text end
    local cut = text:sub(1, max)
    local space = cut:match("^.*()%s")
    if space and space > max / 2 then cut = cut:sub(1, space - 1) end
    -- don't leave half of a UTF-8 letter
    cut = cut:gsub("[\192-\255][\128-\191]*$", function(tail)
        local need = tail:byte(1) >= 240 and 4 or tail:byte(1) >= 224 and 3 or 2
        return #tail == need and tail or ""
    end)
    return ns.Trim(cut)
end

-- $name, $first, $class, $level, $race, $zone and $guild (as <Guild Name>)
-- are replaced. $name is the full Forever name ("Audrey Pichhale"), $first
-- just "Audrey". When the full name makes the
-- whisper too long, the first name alone is used, and as a last resort the
-- message is cut at the last whole word.
function RC:Format(template, p)
    local guild = GuildTag()
    local name = p.short or ns.ShortName(p.full)
    local out = Fill(template, p, name, guild)
    if #out > D.WHISPER_MAX then
        local first = ns.SplitName(name)
        if first ~= "" and first ~= name then out = Fill(template, p, first, guild) end
    end
    return CutAtWord(out, D.WHISPER_MAX)
end

-- The longest `template` can get once filled in (before any shortening):
-- a 25-letter name, your guild's name, and long class, race and zone names.
RC.LONGEST_SAMPLE = { short = "Abcdefghijkl Abcdefghijkl", className = "Warrior", level = 60,
    race = "Night Elf", zone = "Stranglethorn Vale" }
function RC:LongestLength(template)
    return #Fill(template, self.LONGEST_SAMPLE, self.LONGEST_SAMPLE.short, GuildTag())
end

-- "212 / 255", red with a note when the longest name won't fit.
function RC:LengthText(template)
    local n = self:LongestLength(template)
    if n <= D.WHISPER_MAX then return ("%d / %d"):format(n, D.WHISPER_MAX) end
    return ("|cffff2020%d / %d|r (long names: first name only)"):format(n, D.WHISPER_MAX)
end

local function SendWhisper(msg, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, target)
    elseif SendChatMessage then
        SendChatMessage(msg, "WHISPER", nil, target)
    end
end
RC.SendWhisper = SendWhisper

function RC:Whisper(full, customText)
    local p = self:Get(full)
    if not p then return false, "That player is no longer in the list." end
    if self:IsDNW(full) then
        return false, ns.ShortName(full) .. " asked not to be contacted (Do Not Whisper list)."
    end
    p.full, p.short = full, ns.ShortName(full)
    local msg = self:Format(customText or self:TemplateFor(p), p)
    if msg == "" then return false, ("Write a whisper message first (right side of the %s tab)."):format(ns.TabName("recruit")) end
    SendWhisper(msg, ns.ChatName(full))
    p.whispered = ns.DB:Now()
    p.lastWhisper = msg
    self:ShareStatus(full)
    Changed()
    return true, msg
end

------------------------------------------------------------------------
-- Invites
------------------------------------------------------------------------
function RC:CanInvite()
    if not IsInGuild() then return false end
    if CanGuildInvite then return CanGuildInvite() and true or false end
    return true
end

-- Can you invite `full` right now? true, or false and why.
function RC:CanInviteNow(full)
    if self:IsDNW(full) then
        return false, ns.ShortName(full) .. " asked not to be contacted (Do Not Whisper list)."
    end
    local person = self:Get(full)
    if person then person.full = full end
    if not (person and self:Contact(person).whispered) then
        return false, "Whisper " .. ns.ShortName(full) .. " before inviting them."
    end
    if not self:CanInvite() then return false, "Your guild rank can't invite new members." end
    if self:Get(full) and self:Get(full).joined then return false, ns.ShortName(full) .. " already joined." end
    return true
end

-- Records an invite you just sent (from the Invite prompt).
function RC:MarkInvited(full)
    local r = self:Settings()
    local p = r and r.people[full]
    if p then
        p.invited = ns.DB:Now()
        self:ShareStatus(full)
    end
    Changed()
end

-- WoW: Forever blocks addons from calling C_GuildInfo.Invite, so inviting
-- always goes through the Invite prompt, whose button runs /ginvite on your
-- click (UI/InvitePrompt.lua). Returns false and why when it can't.
function RC:Invite(full)
    local ok, err = self:CanInviteNow(full)
    if not ok then return false, err end
    ns.InvitePrompt:Show(full)
    return true
end

-- One-click confirmation (a click always counts as a player action).
function RC:ConfirmInvite(full, reply)
    ns.InvitePrompt:Show(full, reply)
end

-- The game refused something the addon tried (e.g. a timed whisper).
function RC:OnActionBlocked(addon, func)
    if addon == ns.name then self:OnWhisperBlocked(func) end
end

------------------------------------------------------------------------
-- Whisper queue: tick players, then send. Whispers go out one at a time,
-- spaced out. Blizzard publishes no whisper limit; silences come from
-- players reporting spam, so the hourly cap is the user's choice
-- (Options > Recruiting), 40 by default.
------------------------------------------------------------------------
RC.WHISPER_INTERVAL = 12    -- seconds between whispers (at most 300 an hour)
RC.WHISPER_WINDOW = 3600    -- rolling hour for the cap
RC.HOURLY_CHOICES = { 40, 60, 90, 120, 0 } -- 0 = no hourly cap

-- Whispers allowed per rolling hour, or nil for no cap.
function RC:HourlyMax()
    local n = ns.DB:Settings().whisperPerHour
    if n == 0 then return nil end
    return n or 40
end
RC.selected = {}            -- full -> true (this session)
RC.queue = {}               -- fulls waiting to be whispered
RC.sentTimes = {}           -- GetTime() of recent whispers from the queue
RC.clickOnly = false        -- the game blocked a timed whisper this session

-- One click per whisper? Set when the game blocks a timed whisper, until
-- the next login or /reload, when timed whispers are tried again.
function RC:ClickOnly() return self.clickOnly end

-- Players anyone in the guild whispered in the last RECONTACT_DAYS, or a
-- guildmate invited, can't be ticked: one whisper from the guild is enough.
-- Ranks the Guild Master allows to recruit (everyone by default).
-- The game's Invite setting for your rank (Guild Control).
function RC:MayRecruit()
    if not IsInGuild() then return false end
    if IsGuildLeader and IsGuildLeader() then return true end
    if CanGuildInvite then return CanGuildInvite() and true or false end
    return ns.IsOfficer()
end

function RC:CanSelect(p)
    if not self:MayRecruit() then return false end
    if not p or p.joined or p.guild or self:IsDNW(p.full) then return false end
    if self:LockedUntil(p) then return false end
    local c = self:Contact(p)
    if c.by and c.invited then return false end
    return true
end

function RC:SetSelected(full, on)
    self.selected[full] = on and true or nil
    Changed()
end

function RC:SelectedCount()
    local n = 0
    for full in pairs(self.selected) do
        local p = self:Get(full)
        if p and self:CanSelect(p) then n = n + 1 else self.selected[full] = nil end
    end
    return n
end

-- Ticks everyone in `list` who hasn't been whispered yet.
function RC:SelectNew(list)
    for _, p in ipairs(list) do
        if self:CanSelect(p) and not self:IsContacted(p) then self.selected[p.full] = true end
    end
    Changed()
end

function RC:ClearSelection()
    wipe(self.selected)
    Changed()
end

-- Seconds until the queue may send the next whisper.
function RC:WhisperWait()
    local now = GetTime()
    for i = #self.sentTimes, 1, -1 do
        if now - self.sentTimes[i] >= self.WHISPER_WINDOW then table.remove(self.sentTimes, i) end
    end
    local wait = 0
    local last = self.sentTimes[#self.sentTimes]
    if last then wait = self.WHISPER_INTERVAL - (now - last) end
    local max = self:HourlyMax()
    if max and #self.sentTimes >= max then
        wait = math.max(wait, self.WHISPER_WINDOW - (now - self.sentTimes[1]))
    end
    return math.max(0, wait)
end

-- Moves the ticked players (in `order`, the list as shown) into the queue.
function RC:StartSending(order)
    local queued = {}
    for _, f in ipairs(self.queue) do queued[f] = true end
    for _, p in ipairs(order or self:List()) do
        if self.selected[p.full] and self:CanSelect(p) and not queued[p.full] then
            self.queue[#self.queue + 1] = p.full
            queued[p.full] = true
        end
    end
    wipe(self.selected)
    self.queueTotal = (self.queueSent or 0) + #self.queue
    self:Pump()
    Changed()
    return #self.queue
end

function RC:IsQueued(full)
    for _, f in ipairs(self.queue) do if f == full then return true end end
    return false
end

-- Why `full` can't get a recruitment whisper right now, or nil if they can.
-- Same rules as ticking a player on the Recruitment tab. `guild` is the
-- guild /who shows them in, if any.
function RC:WhisperBlocked(full, p, guild)
    if not self:Settings() then return "Join a guild to recruit." end
    if not self:MayRecruit() then return "Your rank can't recruit." end
    if ns.Roster.byName[full] then return "Already in your guild." end
    if (guild and guild ~= "") or (p and p.guild) then return "Already in a guild. Only players without one are recruited." end
    if self:IsDNW(full) then return "On the Do Not Whisper list." end
    p = p or { }
    p.full = full
    local locked = self:LockedUntil(p)
    if locked then
        local c = self:Contact(p)
        local who = c.by and ns.ShortName(c.by) or "You"
        return ("%s whispered them %s. They can be whispered again in %s."):format(who,
            ns.FormatAgo(c.whispered), ns.FormatWait(locked - ns.DB:Now()))
    end
    local c = self:Contact(p)
    if c.by and c.invited then return ("Already invited by %s."):format(ns.ShortName(c.by)) end
end

-- Recruitment whisper from the game's /who window. Adds the player to the
-- recruit list (so the guild sees their status) and to the paced whisper
-- queue, using the same message rules as the Recruitment tab.
-- info: { name, guild, level, classFile, className, zone, race } from /who.
function RC:WhisperFromWho(info)
    local r = self:Settings()
    if not r then return false, "Join a guild to recruit." end
    local full = ns.NormalizeName(info.name)
    if not full then return false end
    local reason = self:WhisperBlocked(full, r.people[full], info.guild)
    if reason then return false, ns.ShortName(full) .. ": " .. reason end
    if self:IsQueued(full) then return true end
    local now = ns.DB:Now()
    local p = r.people[full]
    if not p then
        p = { found = now }
        r.people[full] = p
    end
    p.level = info.level or p.level
    p.classFile, p.className = info.classFile or p.classFile, info.className or p.className
    p.zone, p.race = info.zone or p.zone, info.race or p.race
    p.guild = nil
    p.seen, p.full, p.short = now, full, ns.ShortName(full)
    if self:Format(self:TemplateFor(p), p) == "" then
        return false, ("Write a whisper message first (%s tab)."):format(ns.TabName("recruit"))
    end
    self.queue[#self.queue + 1] = full
    self.queueTotal = (self.queueSent or 0) + #self.queue
    if self:ClickOnly() then
        self:SendNext(true) -- this click can send it, if the spacing allows
    end
    self:Pump()
    Changed()
    return true
end

function RC:StopSending()
    wipe(self.queue)
    self.queueSent, self.queueTotal = 0, 0
    Changed()
end

function RC:IsSending() return #self.queue > 0 end

-- Sends the next queued whisper if the timing allows. Returns true if sent.
function RC:SendNext(fromClick)
    local r = self:Settings()
    if not r or #self.queue == 0 then return false end
    if self:WhisperWait() > 0 then return false end
    if self:ClickOnly() and not fromClick then return false end
    while #self.queue > 0 do
        local full = table.remove(self.queue, 1)
        local p = self:Get(full)
        if p and self:CanSelect(p) then
            self.lastQueued = { full = full, at = GetTime(), auto = not fromClick }
            local ok = self:Whisper(full)
            if ok then
                table.insert(self.sentTimes, GetTime())
                self.queueSent = (self.queueSent or 0) + 1
                if #self.queue == 0 then
                    ns:Print(("Finished sending %d whisper%s."):format(self.queueSent, self.queueSent == 1 and "" or "s"))
                    self.queueSent, self.queueTotal = 0, 0
                end
                Changed()
                return true
            end
        end
    end
    Changed()
    return false
end

function RC:Pump()
    if self.pumping then return end
    self.pumping = true
    local function tick()
        if #RC.queue == 0 then
            RC.pumping = false
            return
        end
        RC:SendNext(false)
        Changed() -- keeps the countdown current
        C_Timer.After(1, tick)
    end
    C_Timer.After(0, tick)
end

-- The game refused a timed whisper: switch to one click per whisper.
function RC:OnWhisperBlocked(func)
    local lq = self.lastQueued
    if not (lq and lq.auto) or GetTime() - lq.at > 2 then return false end
    if func and not tostring(func):find("SendChatMessage", 1, true) then return false end
    self.clickOnly = true
    self.lastBlock = { func = tostring(func or "?"), at = time() }
    local p = self:Get(lq.full)
    if p then
        p.whispered, p.lastWhisper = nil, nil
        self:ShareStatus(lq.full, { whispered = true })
    end
    table.insert(self.queue, 1, lq.full)
    table.remove(self.sentTimes)
    self.queueSent = math.max(0, (self.queueSent or 1) - 1)
    self.lastQueued = nil
    ns:Print("The game blocked a timed whisper, so for the rest of this session click |cffffffffSend Next|r for each whisper (the spacing still applies). After a /reload or your next login, whispers go out on their own again.")
    Changed()
    return true
end

function RC:Diagnose()
    local b = self.lastBlock
    ns:Print(("Whispers: %s%s, %d queued, next in %ds"):format(
        self:ClickOnly() and "one click each (timed whisper blocked this session)" or "timed",
        b and (", blocked: " .. b.func .. " at " .. date("%H:%M", b.at)) or "",
        #self.queue, math.ceil(self:WhisperWait())))
end

------------------------------------------------------------------------
-- Keyword replies
------------------------------------------------------------------------
local function Escape(s)
    return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Returns the keyword found in `text` (whole words, any case), or nil.
-- First word or phrase from `words` found in `text` (whole words, any case).
local function MatchWords(words, text)
    if not words or not text then return nil end
    local lower = text:lower()
    for _, kw in ipairs(words) do
        kw = ns.Trim(kw):lower()
        if kw ~= "" then
            local pattern = Escape(kw)
            if kw:match("^%w") then pattern = "%f[%w]" .. pattern end
            if kw:match("%w$") then pattern = pattern .. "%f[%W]" end
            if lower:find(pattern) then return kw end
        end
    end
end

function RC:MatchKeyword(text)
    local r = self:Settings()
    return r and MatchWords(r.keywords, text)
end

function RC:MatchDNW(text)
    local r = self:Settings()
    return r and MatchWords(r.dnwWords, text)
end

------------------------------------------------------------------------
-- Do Not Whisper list (shared with everyone in the guild using the addon)
-- Stored as sync records DN:<player> = "time;what they said" ("" = removed),
-- so whoever gets the reply protects that player for the whole guild.
------------------------------------------------------------------------
local function DNKey(full) return "DN:" .. full end

function RC:IsDNW(full)
    if not full then return false end
    local v = ns.Sync:Value(DNKey(full))
    return v ~= nil and v ~= ""
end

function RC:AddDNW(full, reply)
    if not full or not ns.DB:Guild() then return end
    local text = ns.Sync.Clean(reply or ""):gsub(";", ","):sub(1, 80)
    local ok = ns.Sync:Set(DNKey(full), ("%d;%s"):format(ns.DB:Now(), text))
    Changed()
    return ok
end

function RC:RemoveDNW(full)
    if not self:MayRecruit() then
        ns:Print("|cffff2020Only ranks the Guild Master lets recruit can take people off the Do Not Whisper list.|r")
        return
    end
    if self:IsDNW(full) then
        ns.Sync:Set(DNKey(full), "")
        Changed()
    end
end

-- { { full, at, reply, by }, ... } newest first
function RC:DNWList()
    local out = {}
    local store = ns.Sync:Store("guild")
    if not store then return out end
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "DN:" and rec.v ~= "" then
            local at, reply = rec.v:match("^(%d+);(.*)$")
            out[#out + 1] = { full = key:sub(4), at = tonumber(at) or rec.t, reply = reply, by = rec.a }
        end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.full < b.full
    end)
    return out
end

-- People someone in the guild whispered in the last RECONTACT_DAYS (and
-- who aren't on the Do Not Whisper list), most recent first:
-- { { full, whispered, untilT, by, replied, invited, reply }, ... }
-- Built from the shared RS records, so every recruiter sees the same list.
function RC:LockedList()
    local out = {}
    local store = ns.Sync:Store("guild")
    if not store then return out end
    local now = ns.DB:Now()
    local span = self.RECONTACT_DAYS * 86400
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "RS:" and rec.v ~= "" then
            local full = key:sub(4)
            local sh = self:Shared(full)
            if sh and sh.w and sh.w + span > now and not self:IsDNW(full) then
                out[#out + 1] = { full = full, whispered = sh.w, untilT = sh.w + span, by = sh.by,
                    replied = sh.r, invited = sh.i, reply = sh.reply }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.whispered ~= b.whispered then return a.whispered > b.whispered end
        return a.full < b.full
    end)
    return out
end

-- 1.08 kept the list on each computer only: share it once.
function RC:MigrateDNW()
    local r = self:Settings()
    if not r or not r.dnw or not next(r.dnw) then return end
    for full, d in pairs(r.dnw) do
        if not self:IsDNW(full) then self:AddDNW(full, d.reply) end
    end
    r.dnw = nil
end

-- Your own whispers to someone the addon whispered: after one of these
-- their replies are a conversation with you, not an answer to the addon.
function RC:OnWhisperSent(text, target)
    local full = ns.NormalizeName(target)
    local p = full and self:Get(full)
    if not (p and p.whispered) then return end
    if text == p.lastWhisper then return end -- the addon's own whisper (or you sending it in click mode)
    p.talkedAt = ns.DB:Now()
end

-- Is this reply an answer to the addon's whisper? Only then can it put
-- someone on the Do Not Whisper list.
RC.REPLY_WINDOW = 86400
function RC:AnswersAddonWhisper(p)
    if not p.whispered or ns.DB:Now() - p.whispered > self.REPLY_WINDOW then return false end
    return not (p.talkedAt and p.talkedAt >= p.whispered)
end

function RC:OnWhisper(text, sender)
    local full = ns.NormalizeName(sender)
    local p = full and self:Get(full)
    if not (p and p.whispered) or p.joined then return end
    p.replied = ns.DB:Now()
    p.reply = text
    p.full = full
    self:ShareStatus(full)
    ns.PlaySound("TELL_MESSAGE")

    local r = self:Settings()
    local keyword = r.autoInvite and not p.invited and self:MatchKeyword(text)
    local dnw = r.dnwEnabled and self:AnswersAddonWhisper(p) and self:MatchDNW(text)
    if dnw and keyword then
        -- "no guild yet, inv pls": both kinds of word. Don't decide for them.
        ns:Print(("%s replied \"%s\" - that has both a Do Not Whisper word and an invite keyword, so they weren't added to the list."):format(ns.ShortName(full), text))
        self:ConfirmInvite(full, text)
        Changed()
        return
    elseif dnw then
        self:AddDNW(full, text)
        ns:Print(("%s replied \"%s\" - added to the Do Not Whisper list. They won't be whispered or invited again."):format(ns.ShortName(full), dnw))
        return
    end
    if keyword then
        ns:Print(("%s replied \"%s\" - click Invite to send them a guild invite."):format(ns.ShortName(full), keyword))
        self:ConfirmInvite(full, text)
    end
    Changed()
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function RC:Init()
    ns:RegisterEvent("WHO_LIST_UPDATE", function() RC:OnWhoResults() end)
    ns:RegisterEvent("CHAT_MSG_WHISPER", function(_, text, sender) RC:OnWhisper(text, sender) end)
    ns:RegisterEvent("CHAT_MSG_WHISPER_INFORM", function(_, text, target) RC:OnWhisperSent(text, target) end)
    ns:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon, func) RC:OnActionBlocked(addon, func) end)
    ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", function(_, addon, func) RC:OnActionBlocked(addon, func) end)

    -- Mark invited players who show up in the roster as joined.
    ns:On("ROSTER_UPDATED", function()
        if not RC.dnwMigrated and ns.DB:Guild() then
            RC.dnwMigrated = true
            RC:MigrateDNW()
        end
        local r = RC:Settings()
        if not r then return end
        local changed = false
        for full, p in pairs(r.people) do
            if not p.joined and ns.Roster.byName[full] then
                p.joined = ns.DB:Now()
                changed = true
            end
        end
        if changed then Changed() end
    end)
end
