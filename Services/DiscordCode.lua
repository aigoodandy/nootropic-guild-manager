--[[
    Nootropic Guild Manager - NGM Peon setup code (3.0)
    The Guild Master's copy makes a short code for NGM Peon's /ngm setup in
    Discord. It carries what Blizzard's web API can't: the guild's rank
    names, and which ranks the game marks Officer and Invite Member.

        NGM1.<payload, base64url>.<adler-32 of the payload, 8 hex digits>

    The payload is lines: region (us/eu), guild name, then one line per rank
    (rank 0 first): two flags ("O" Officer or "-", "I" Invite or "-"), a
    colon, the rank name. NGM Peon reads it in ngm-hub's src/setupcode.ts;
    tests/test_discord_code.lua checks both sides make the same code.

    The code proves nothing by itself: NGM Peon still has the Guild Master
    sign in with Battle.net.

    NGM2, the update code (pasted on the dashboard's Sync tab, step 2), is NGM1's
    lines, an empty line, then what changed in game:
        since<TAB>t                 changes after this time (0 = everything)
        upto<TAB>t                  when the code was made
        hours<TAB>n<TAB>c,c,...     people sharing hours, then the 84 When we
                                    play counts (7 days x 12 two-hour blocks,
                                    server time, Monday first), as the Overview
        R<TAB>key<TAB>t<TAB>author<TAB>value   main/alt (M) and roles (RL)
    Times are server time in seconds, in base 36. Only changes are sent:
    since = what NGM Peon last said it has, else the last code made, less two
    weeks (a code made but never pasted is covered). Newest wins on both
    sides, so sending something twice is harmless. /ngm discord all sends
    everything; /ngm discord setup makes the short NGM1 code.

    ns.DiscordCode:Make(region, guild, ranks) -> code
    ns.DiscordCode:MakeUpdate(region, guild, ranks, update) -> code
    ns.DiscordCode:ForMyGuild(mode)           -> code, or nil and why
                                                 (mode: nil, "all" or "setup");
                                                 update codes also: everything?,
                                                 how many records, since when
]]
local _, ns = ...
local DC = {}
ns.DiscordCode = DC

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- base64url, no padding. Arithmetic only (no bit library needed).
function DC.Base64Url(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
        if b then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) end
        if c then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) end
    end
    return table.concat(out)
end

-- Adler-32 as 8 hex digits, written as two halves (the game's string.format
-- can't print numbers past 2^31 in hex).
function DC.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b, a)
end


local function B36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local d, out = "0123456789abcdefghijklmnopqrstuvwxyz", {}
    while n > 0 do
        local r = n % 36
        table.insert(out, 1, d:sub(r + 1, r + 1))
        n = math.floor(n / 36)
    end
    return table.concat(out)
end
DC.B36 = B36

local function RankLines(region, guild, ranks)
    local lines = { region, guild }
    for _, r in ipairs(ranks) do
        lines[#lines + 1] = (r.officer and "O" or "-") .. (r.invite and "I" or "-") .. ":" .. r.name
    end
    return lines
end

-- ranks: { { name =, officer =, invite = }, ... } in rank order, 0 first
function DC:Make(region, guild, ranks)
    local payload = table.concat(RankLines(region, guild, ranks), "\n")
    return "NGM1." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
end

-- The hours line's value ("<sharing>\t<count>,<count>,..."), as NGM Peon
-- hashes it to say which grid it has.
function DC.HoursValue(hours)
    local c = {}
    for i = 1, 84 do c[i] = B36(hours.counts[i] or 0) end
    return B36(hours.sharing) .. "\t" .. table.concat(c, ",")
end

-- update: { since =, upto =, hours = { sharing =, counts = {84} } or nil,
--           records = { { key =, v =, t =, a = }, ... },
--           tabard = { bg =, border = } (hex) or nil }
function DC:MakeUpdate(region, guild, ranks, update)
    local lines = RankLines(region, guild, ranks)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "since\t" .. B36(update.since)
    lines[#lines + 1] = "upto\t" .. B36(update.upto)
    if update.hours then lines[#lines + 1] = "hours\t" .. DC.HoursValue(update.hours) end
    -- the tabard's colours, for NGM Peon's accent (left out while unknown)
    if update.tabard and update.tabard.bg and update.tabard.border then
        lines[#lines + 1] = "accent\t" .. update.tabard.bg .. "," .. update.tabard.border
            .. (update.tabard.emblem and ("," .. update.tabard.emblem) or "")
    end
    for _, r in ipairs(update.records) do
        lines[#lines + 1] = "R\t" .. r.key .. "\t" .. B36(r.t) .. "\t" .. r.a .. "\t" .. r.v
    end
    local payload = table.concat(lines, "\n")
    return "NGM2." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
end

DC.OVERLAP = 14 * 86400 -- before NGM Peon's word: a code made but never pasted is covered
DC.ARRIVAL = 7 * 86400  -- after it: a record written days before it reached the Guild Master's game is covered

-- Main/alt and roles records changed after `since`, oldest first.
function DC:Changes(since)
    local out = {}
    local store = ns.Sync:Store("guild") or {}
    for key, rec in pairs(store) do
        local typ = key:match("^(%u+):")
        if (typ == "M" or typ == "RL") and (rec.t or 0) > since and rec.a and rec.a ~= ""
            and ns.Sync.ValidValue(typ, rec.v) then
            out[#out + 1] = { key = key, v = rec.v or "", t = rec.t, a = rec.a }
        end
    end
    table.sort(out, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.key < y.key end)
    return out
end

-- The Overview's When we play, counted as its default view (active in 30
-- days, a player's characters once): 84 counts, Monday 00:00 first.
function DC:Hours()
    if not (ns.OverviewView and ns.OverviewView.Census) then return nil end
    local c = ns.OverviewView:Census(30, false)
    local counts = {}
    for k = 0, 83 do counts[k + 1] = c.heat[k] or 0 end
    return { sharing = c.sharing or 0, counts = counts }
end

local REGIONS = { [1] = "us", [3] = "eu" }

function DC:Region()
    local ok, id = pcall(function() return GetCurrentRegion and GetCurrentRegion() end)
    return ok and REGIONS[id] or nil
end

-- The code for the player's own guild. Only the Guild Master's game is
-- sure to see every rank's settings, so only the Guild Master makes it.
-- The guild's ranks as the game has them: { { name, officer, invite } }, or nil and why.
function DC:MyRanks()
    local ranks = {}
    for _, r in ipairs(ns.DB:GuildRanks()) do
        local f = r.index == 0 and { officer = true, invite = true } or ns.Sync:RankFlags(r.index)
        if not f then
            return nil, "The game isn't sharing your ranks' settings right now. Open the guild window's rank settings once, then try again."
        end
        if r.name:find("\n", 1, true) then return nil, "A rank name has a line break in it." end
        ranks[#ranks + 1] = { name = r.name, officer = f.officer, invite = f.invite }
    end
    if #ranks < 2 then return nil, "The game hasn't loaded your guild's ranks yet. Try again in a moment." end
    return ranks
end

function DC.RankSignature(ranks)
    local parts = {}
    for i, r in ipairs(ranks) do parts[i] = (r.officer and "O" or "-") .. (r.invite and "I" or "-") .. r.name end
    return table.concat(parts, "\n")
end

function DC:ForMyGuild(mode)
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil, "You're not in a guild." end
    if not (ns.DB.IsGuildMaster and ns.DB:IsGuildMaster()) then
        return nil, "Only the Guild Master can make the setup code: only their game sees every rank's settings."
    end
    local region = self:Region()
    if not region then return nil, "NGM Peon serves the US and EU regions only, for now." end
    local ranks, why = self:MyRanks()
    if not ranks then return nil, why end
    if mode == "setup" then return self:Make(region, guild, ranks) end
    -- the update code: only what changed since NGM Peon last had it all
    local g = ns.DB:Guild() or {}
    g.peon = g.peon or {}
    local upto = ns.DB:Now()
    local since = 0
    if mode ~= "all" then
        if g.peon.has then since = math.max(0, g.peon.has - self.ARRIVAL)
        elseif g.peon.made then since = math.max(0, g.peon.made - self.OVERLAP) end
    end
    local records = self:Changes(since)
    -- the When we play grid only when NGM Peon's differs (or everything was asked for)
    local hours = self:Hours()
    if hours and since > 0 and g.peon.hoursHash and ns.Sync.Hash(self.HoursValue(hours)) == g.peon.hoursHash then hours = nil end
    -- (not "ns.Accent and ns.Accent:Tabard()": that keeps only the first colour)
    local bg, border, emblem
    if ns.Accent then bg, border, emblem = ns.Accent:Tabard() end
    local tabard = (bg and border) and { bg = bg, border = border, emblem = emblem } or nil
    local code = self:MakeUpdate(region, guild, ranks, { since = since, upto = upto, hours = hours, records = records, tabard = tabard })
    g.peon.made = upto
    g.peon.ranks = self.RankSignature(ranks)
    return code, nil, since == 0, #records, since
end

------------------------------------------------------------------------
-- The code from NGM Peon (/ngm peon): NGMP1.<base64url>.<adler-32>
--   region, guild, has<TAB>t, [hours<TAB>hash], R<TAB>key<TAB>t<TAB>author<TAB>value
--   (records: M main/alt, RL Tank/Healer/DPS, CN a linked member's @Discord name,
--   HW a month's Hall of Fame champions, GS:peon = "1": NGM Peon crowns them)
-- (ngm-hub's src/records/addoncode.ts makes it). Its records are taken as
-- if the player pasting it had passed them on in guild sync: under the same
-- rules (an officer may pass on anyone's; anyone else only their own), then
-- shared with the guild.
------------------------------------------------------------------------
local B64DEC = {}
for i = 1, 64 do B64DEC[B64:byte(i)] = i - 1 end

function DC.Base64UrlDecode(s)
    local out, n = {}, #s
    for i = 1, n, 4 do
        local a, b, c, d = B64DEC[s:byte(i)], B64DEC[s:byte(i + 1) or 0], B64DEC[s:byte(i + 2) or 0], B64DEC[s:byte(i + 3) or 0]
        if a == nil or b == nil then return nil end
        if s:byte(i + 2) and c == nil or s:byte(i + 3) and d == nil then return nil end
        local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        out[#out + 1] = string.char(math.floor(v / 65536) % 256)
        if c then out[#out + 1] = string.char(math.floor(v / 256) % 256) end
        if d then out[#out + 1] = string.char(v % 256) end
    end
    return table.concat(out)
end

-- code -> { region, guild, has, hoursHash, records = { {key, t, a, v} } }, or nil and why
function DC:ParsePeon(code)
    code = (code or ""):gsub("%s+", "")
    if code == "" then return nil, "Paste the code from NGM Peon's dashboard (ngmpeon.app, Sync tab, step 3)." end
    local body, sum = code:match("^NGMP1%.([A-Za-z0-9_%-]+)%.(%x%x%x%x%x%x%x%x)$")
    if not body then return nil, "That isn't a code from NGM Peon. It starts with NGMP1." end
    local payload = DC.Base64UrlDecode(body)
    if not payload or DC.Adler32(payload) ~= sum:lower() then return nil, "The code doesn't check out. Copy it again from the dashboard." end
    local lines = {}
    for line in (payload .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local out = { region = lines[1], guild = lines[2], records = {}, events = {} }
    for i = 3, #lines do
        local f = ns.Split(lines[i], "\t")
        if f[1] == "has" then out.has = tonumber(f[2] or "", 36)
        elseif f[1] == "hours" then out.hoursHash = tonumber(f[2] or "", 36)
        elseif f[1] == "E" and #f >= 7 then
            -- an upcoming event (Services/Events.lua): where to sign up and who's coming
            local id, starts, minutes = tonumber(f[2], 36), tonumber(f[4], 36), tonumber(f[5], 36)
            if not (id and starts and minutes) then return nil, "The code looks damaged. Copy it again from the dashboard." end
            out.events[#out.events + 1] = { id = id, kind = f[3], starts = starts, minutes = minutes, title = f[6], description = f[7] or "",
                channel = f[8] or "", server = f[9] or "", coming = tonumber(f[10] or "", 36) or 0 }
        elseif f[1] == "R" and #f >= 5 then
            local t = tonumber(f[3], 36)
            if not t then return nil, "The code looks damaged. Copy it again from the dashboard." end
            out.records[#out.records + 1] = { key = f[2], t = t, a = f[4], v = table.concat(f, "\t", 5) }
        elseif lines[i] ~= "" then
            return nil, "The code looks damaged. Copy it again from the dashboard."
        end
    end
    if not out.has then return nil, "The code looks damaged. Copy it again from the dashboard." end
    return out
end

-- Brings a code from NGM Peon in. -> { taken, had, refused, players,
-- characters, names }, or nil and why. players: whose main/alts changed;
-- characters: whose Tank/Healer/DPS changed; names: Discord names taken.
function DC:ApplyPeon(code)
    local c, why = self:ParsePeon(code)
    if not c then return nil, why end
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil, "You're not in a guild." end
    if c.guild:lower() ~= guild:lower() or (self:Region() and c.region ~= self:Region()) then
        return nil, ("That code is for <%s>, not <%s>."):format(c.guild, guild)
    end
    local out = { taken = 0, had = 0, refused = 0, players = 0, characters = 0, names = 0, months = 0 }
    local mains = {}
    for _, r in ipairs(c.records) do
        local typ = r.key:match("^(%u+):")
        -- mains, roles, Discord names, champions, and the setting that NGM Peon crowns them
        local wanted = typ == "M" or typ == "RL" or typ == "CN" or (typ == "HW" and r.key:match("^HW:%d%d%d%d%d%d$")) or r.key == "GS:peon"
        if not wanted then
            out.refused = out.refused + 1
        else
            local cur = ns.Sync:Get(r.key)
            if cur and cur.t >= r.t then
                out.had = out.had + 1
            else
                local ok, key = ns.Sync:Intake(r.key, r.t, r.a, nil, r.v, { origin = "remote", channel = "GUILD", sender = ns.PlayerFullName() })
                if ok then
                    out.taken = out.taken + 1
                    ns.Sync:Broadcast(key, ns.Sync:Get(key))
                    local who = key:match("^%u+:(.*)$")
                    if typ == "M" then
                        local main = (r.v ~= "" and r.v) or who
                        if not mains[main] then mains[main] = true; out.players = out.players + 1 end
                    elseif typ == "RL" then out.characters = out.characters + 1
                    elseif typ == "CN" then out.names = out.names + 1
                    elseif typ == "HW" then out.months = out.months + 1 end
                else
                    out.refused = out.refused + 1
                end
            end
        end
    end
    local g = ns.DB:Guild() or {}
    g.peon = g.peon or {}
    if not g.peon.has or c.has > g.peon.has then g.peon.has = c.has end
    g.peon.hoursHash = c.hoursHash
    -- when the guild last brought NGM Peon's code in (for the reminder); officers share it
    if ns.Sync.CanWrite and ns.Sync:CanWrite("GS:peonat") then ns.Sync:Set("GS:peonat", tostring(ns.DB:Now())) end
    -- Upcoming Events (shared with the guild by an officer)
    if ns.Events then out.events, out.eventsNew, out.eventsRemoved = ns.Events:Take(c.events) end
    return out
end

------------------------------------------------------------------------
-- The reminder: the Guild Master of a guild using NGM Peon is told when the
-- two are out of step: 3 days or more since the last update code (game to
-- Discord) or since anyone in the guild brought in NGM Peon's code (Discord
-- to the game; GS:peonat, written by the officer who did), or the ranks
-- changed in game since. Once a day (ranks: once per change), never in combat.
------------------------------------------------------------------------
DC.REMIND_AFTER = 3 * 86400

-- The reminder's text now and why ("ranks", "never" or "days"), or nil.
function DC:ReminderText(now)
    now = now or ns.DB:Now()
    if not (ns.DB.IsGuildMaster and ns.DB:IsGuildMaster()) then return nil end
    local g = ns.DB:Guild()
    if not g then return nil end
    local peon = g.peon or {}
    if not (peon.made or ns.Sync:Value("GS:peon") == "1") then return nil end -- not using NGM Peon
    local toDiscord = "Type |cffffffff/ngm discord|r and paste it on |cffffffffngmpeon.app|r (Sync tab, step 2)."
    local ranks = self:MyRanks()
    if ranks and peon.ranks and self.RankSignature(ranks) ~= peon.ranks then
        return "your guild's ranks changed since you last updated NGM Peon. " .. toDiscord, "ranks", self.RankSignature(ranks)
    end
    -- what's overdue, each way (best done daily; told after REMIND_AFTER)
    local function ago(t) return t and math.floor((now - t) / 86400) or nil end
    local sent = ago(peon.made)
    local rec = ns.Sync:Get("GS:peonat") -- when anyone in the guild last brought in NGM Peon's code
    local got = ago(rec and tonumber(rec.v))
    local late = self.REMIND_AFTER / 86400
    local lines = {}
    if not sent or sent >= late then
        lines[#lines + 1] = ("  " .. ns.GOLD .. "Game to Discord|r: ") .. (sent and ("last done %d days ago. "):format(sent) or "not done yet. ") .. toDiscord
    end
    if not got or got >= late then
        lines[#lines + 1] = ("  " .. ns.GOLD .. "Discord to the game|r: ") .. (got and ("last done %d days ago. "):format(got) or "not done yet. ")
            .. "Copy the Sync tab's step 3 code, type |cffffffff/ngm peon|r and press Bring In."
    end
    if #lines == 0 then return nil end
    return "time to sync with NGM Peon (best done daily).\n" .. table.concat(lines, "\n"), "days"
end

function DC:Remind(now)
    now = now or ns.DB:Now()
    if InCombatLockdown and InCombatLockdown() then return false end
    local text, why, ranks = self:ReminderText(now)
    if not text then return false end
    local g = ns.DB:Guild()
    g.peon = g.peon or {}
    if why == "ranks" then
        -- once per change of ranks (a later change the same day is told too)
        if g.peon.remindedRanks == ranks then return false end
        g.peon.remindedRanks = ranks
    else
        local today = date("!%Y%m%d", now)
        if g.peon.remindedOn == today then return false end
        g.peon.remindedOn = today
    end
    ns:Print(text)
    return true
end

function DC:Init()
    local remind = ns.Safe and ns.Safe(function() DC:Remind() end, "DiscordCode") or function() DC:Remind() end
    C_Timer.After(60, remind) -- after login, once the roster and ranks are in
    -- ranks renamed or their permissions changed during the session
    ns:RegisterEvent("GUILD_RANKS_UPDATE", function() ns.Debounce("peonranks", 5, remind) end)
end
