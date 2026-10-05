--[[
    Nootropic Guild Manager - Recruitment service
    Runs /who searches for unguilded players, remembers who you've contacted,
    fills in per-class whisper templates, sends guild invites, and invites
    automatically when a whispered player replies with one of your keywords.

    Saved per guild in guild.recruit:
      default    = "whisper used when a class has no message of its own"
      templates  = { [CLASSFILE] = "..." }
      keywords   = { "invite", ... }          -- up to 5
      autoInvite = true                       -- invite on a keyword reply
      inviteMode = "auto" | "confirm"         -- confirm = one-click popup
      query      = { min, max, class, zone, step, guildOn, guild, name, hideContacted,
                     zoneAuto, levelAuto }       -- *Auto: follow the player (see ApplyAutoQuery)
      people     = { ["Name-Realm"] = { level, classFile, className, zone, guild,
                     found, seen, whispered, replied, reply, invited, joined } }
      dnwEnabled = true                       -- watch replies for Do Not Whisper words
      dnwWords   = { "dnw", "leave me alone", ... }   -- up to 5
      (the Do Not Whisper list itself is shared: sync records DN:<player>)
      (statuses are shared for 7 days: sync records RS:<player>, see Contact)
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
    if not r.keywords then
        r.keywords = {}
        for i, k in ipairs(D.DEFAULT_KEYWORDS) do r.keywords[i] = k end
    end
    if r.autoInvite == nil then r.autoInvite = true end
    r.inviteMode = r.inviteMode or "confirm" -- WoW: Forever only allows guild invites from a click
    r.people = r.people or {}
    r.query = r.query or { min = 1, max = 60, step = false }
    if r.query.guildOn == nil then r.query.guildOn = false end
    r.query.guild = r.query.guild or ""
    r.query.name = r.query.name or ""
    if r.dnwEnabled == nil then r.dnwEnabled = true end
    r.whisperMode = r.whisperMode or "auto" -- "click" if this client blocks timed whispers
    ns.Messages:Migrate(r)
    if not r.dnwWords then
        r.dnwWords = {}
        for i, w in ipairs(D.DEFAULT_DNW_WORDS) do r.dnwWords[i] = w end
    end
    if not self.pruned then
        self.pruned = true
        local cutoff = ns.DB:Now() - PRUNE_AFTER
        for full, p in pairs(r.people) do
            if not p.whispered and not p.invited and (p.seen or 0) < cutoff then r.people[full] = nil end
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
-- invited;reply", times or empty). Records expire after 7 days.
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
    if name ~= "" then parts[#parts + 1] = ('n-"%s"'):format((name:gsub('"', ""))) end
    parts[#parts + 1] = ("%d-%d"):format(lo, hi)
    if q.class then parts[#parts + 1] = ('c-"%s"'):format(D:ClassName(q.class)) end
    local zone = ns.Trim(q.zone)
    if zone ~= "" then parts[#parts + 1] = ('z-"%s"'):format((zone:gsub('"', ""))) end
    local guild = ns.Trim(q.guild)
    if q.guildOn and guild ~= "" then parts[#parts + 1] = ('g-"%s"'):format((guild:gsub('"', ""))) end
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
    if r.query.guildOn and ns.Trim(r.query.guild) == "" then
        return nil, "Type the guild name to search for, or untick Guild."
    end
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
        if err then ns:Print("|cffff5555" .. err .. "|r") end
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
    -- Normal searches keep players without a guild; a guild search keeps
    -- members of the guild typed in (never our own).
    local want = r.query.guildOn and ns.Trim(r.query.guild):lower() or nil
    if want == "" then want = nil end
    local mine = (GetGuildInfo("player") or ""):lower()
    for i = 1, shown do
        local name, guild, level, className, classFile, zone, race, sex = ReadWho(i)
        guild = guild or ""
        local keep
        if want then
            -- the guild name as typed, or the start of it ("Night" finds "Night Watch")
            local g = guild:lower()
            keep = g ~= "" and g ~= mine and g:sub(1, #want) == want
        else
            keep = guild == ""
        end
        if name and keep then
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
                    p.guild = guild ~= "" and guild or nil
                    p.race, p.sex = race, sex
                end
            end
        end
    end
    self.last = { query = self.pendingQuery, shown = shown, total = total or shown, unguilded = matched,
        matched = matched, new = new, skipped = skipped, guild = want and ns.Trim(r.query.guild) or nil }

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

-- $name, $class, $level, $race, $zone and $guild (as <Guild Name>) are replaced.
function RC:Format(template, p)
    local guild = GetGuildInfo("player")
    guild = (guild and guild ~= "") and ("<" .. guild .. ">") or ""
    local out = (template or ""):gsub("%$(%a+)", function(key)
        key = key:lower()
        if key == "name" then return p.short or ns.ShortName(p.full)
        elseif key == "class" then return p.className or D:ClassName(p.classFile)
        elseif key == "level" then return tostring(p.level or "")
        elseif key == "guild" then return guild
        elseif key == "race" then return p.race or ""
        elseif key == "zone" then return p.zone or ""
        end
    end)
    out = out:gsub("[\r\n]+", " ")
    return ns.Trim(out):sub(1, D.WHISPER_MAX)
end

local function SendWhisper(msg, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, target)
    elseif SendChatMessage then
        SendChatMessage(msg, "WHISPER", nil, target)
    end
end

function RC:Whisper(full, customText)
    local p = self:Get(full)
    if not p then return false, "That player is no longer in the list." end
    if self:IsDNW(full) then
        return false, ns.ShortName(full) .. " asked not to be contacted (Do Not Whisper list)."
    end
    p.full, p.short = full, ns.ShortName(full)
    local msg = self:Format(customText or self:TemplateFor(p), p)
    if msg == "" then return false, "Write a whisper message first (right side of the Recruitment tab)." end
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

function RC:Invite(full, automatic)
    if self:IsDNW(full) then
        return false, ns.ShortName(full) .. " asked not to be contacted (Do Not Whisper list)."
    end
    local person = self:Get(full)
    if person then person.full = full end
    if not (person and self:Contact(person).whispered) then
        return false, "Whisper " .. ns.ShortName(full) .. " before inviting them."
    end
    if not self:CanInvite() then return false, "Your guild rank can't invite new members." end
    self.lastInvite = { full = full, at = GetTime(), automatic = automatic }
    local target = ns.ChatName(full)
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(target)
    elseif GuildInvite then
        GuildInvite(target)
    end
    local r = self:Settings()
    local p = r and r.people[full]
    if p then
        p.invited = ns.DB:Now()
        self:ShareStatus(full)
    end
    Changed()
    return true
end

-- One-click confirmation (a click always counts as a player action).
function RC:ConfirmInvite(full, reply)
    StaticPopup_Show("NOOTROPICGM_INVITE", ns.ShortName(full), reply or "", { full = full })
end

-- If the game refuses an automatic invite, switch to one-click confirmation.
function RC:OnActionBlocked(addon, func)
    if addon == ns.name and self:OnWhisperBlocked(func) then return end
    local li = self.lastInvite
    if addon ~= ns.name or not (li and li.automatic) or GetTime() - li.at > 2 then return end
    local r = self:Settings()
    if not r then return end
    r.inviteMode = "confirm"
    local p = r.people[li.full]
    if p then
        p.invited = nil
        self:ShareStatus(li.full, { invited = true })
    end
    self.lastInvite = nil
    ns:Print("This game client only allows guild invites from a click, so Nootropic Guild Manager will now pop up an Invite button when someone replies with a keyword.")
    self:ConfirmInvite(li.full, p and p.reply)
    Changed()
end

------------------------------------------------------------------------
-- Whisper queue: tick players, then send. Whispers go out one at a time,
-- spaced out so the game's spam detection is never triggered.
------------------------------------------------------------------------
RC.WHISPER_INTERVAL = 12    -- seconds between whispers
RC.WHISPER_WINDOW = 3600    -- rolling hour...
RC.WHISPER_MAX = 40         -- ...and how many whispers it allows
RC.selected = {}            -- full -> true (this session)
RC.queue = {}               -- fulls waiting to be whispered
RC.sentTimes = {}           -- GetTime() of recent whispers from the queue

-- Players a guildmate already contacted (shared status) can't be ticked:
-- one whisper from the guild is enough.
function RC:CanSelect(p)
    if not p or p.joined or self:IsDNW(p.full) then return false end
    local c = self:Contact(p)
    if c.by and (c.whispered or c.invited) then return false end
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
    if #self.sentTimes >= self.WHISPER_MAX then
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
-- Same rules as ticking a player on the Recruitment tab.
function RC:WhisperBlocked(full, p)
    if not self:Settings() then return "Join a guild to recruit." end
    if ns.Roster.byName[full] then return "Already in your guild." end
    if self:IsDNW(full) then return "On the Do Not Whisper list." end
    if p then
        p.full = full
        local c = self:Contact(p)
        if c.by and (c.whispered or c.invited) then
            return ("Already contacted by %s."):format(ns.ShortName(c.by))
        end
        if c.whispered then return "You already whispered them." end
    end
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
    local reason = self:WhisperBlocked(full, r.people[full])
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
    p.guild = (info.guild and info.guild ~= "") and info.guild or nil
    p.seen, p.full, p.short = now, full, ns.ShortName(full)
    if self:Format(self:TemplateFor(p), p) == "" then
        return false, "Write a whisper message first (Recruitment tab)."
    end
    self.queue[#self.queue + 1] = full
    self.queueTotal = (self.queueSent or 0) + #self.queue
    if r.whisperMode == "click" then
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
    if r.whisperMode == "click" and not fromClick then return false end
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
    local r = self:Settings()
    r.whisperMode = "click"
    local p = self:Get(lq.full)
    if p then
        p.whispered, p.lastWhisper = nil, nil
        self:ShareStatus(lq.full, { whispered = true })
    end
    table.insert(self.queue, 1, lq.full)
    table.remove(self.sentTimes)
    self.queueSent = math.max(0, (self.queueSent or 1) - 1)
    self.lastQueued = nil
    ns:Print("This game client only sends whispers from a click. Click |cffffffffSend Next|r for each whisper; the spacing between whispers still applies.")
    Changed()
    return true
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

-- 1.08 kept the list on each computer only: share it once.
function RC:MigrateDNW()
    local r = self:Settings()
    if not r or not r.dnw or not next(r.dnw) then return end
    for full, d in pairs(r.dnw) do
        if not self:IsDNW(full) then self:AddDNW(full, d.reply) end
    end
    r.dnw = nil
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
    -- Do Not Whisper wins over invite keywords
    local dnw = r.dnwEnabled and self:MatchDNW(text)
    if dnw then
        self:AddDNW(full, text)
        ns:Print(("%s replied \"%s\" - added to the Do Not Whisper list. They won't be whispered or invited again."):format(ns.ShortName(full), dnw))
        return
    end
    local keyword = r.autoInvite and not p.invited and self:MatchKeyword(text)
    if keyword then
        if r.inviteMode == "confirm" or not self:CanInvite() then
            self:ConfirmInvite(full, text)
        else
            ns:Print(("%s replied \"%s\" - sending a guild invite."):format(ns.ShortName(full), keyword))
            self:Invite(full, true)
        end
    end
    Changed()
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
StaticPopupDialogs.NOOTROPICGM_INVITE = {
    text = "|cffffd100%s|r replied:\n\"%s\"\n\nInvite them to the guild?",
    button1 = "Invite",
    button2 = CANCEL or "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        data = data or self.data
        if data and data.full then
            local ok, err = RC:Invite(data.full, false)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end
    end,
}

function RC:Init()
    ns:RegisterEvent("WHO_LIST_UPDATE", function() RC:OnWhoResults() end)
    ns:RegisterEvent("CHAT_MSG_WHISPER", function(_, text, sender) RC:OnWhisper(text, sender) end)
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
