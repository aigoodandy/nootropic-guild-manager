--[[
    Nootropic Guild Manager - Profile extras
    About me, status line, usual online hours and anonymous kudos.

    About me (AB:<member>)
      Up to 300 characters and 3 line breaks, written by the member. An alt
      without one shows its main's. Officers can clear one, never edit it.

    Status (ST:<member>)
      Up to 80 characters; the record's time says when it was set.

    Usually online (SC:<member>)
      Learned from when you actually play (your own copy notes it, last 4
      weeks), with optional per-day hours you set. Kept and shared in server
      time; shown in local or server time the way your game clock is set
      (see the "Usually online" section below).

    Kudos (KT:<id> types, KU:<member>:<type>:<id> kudos)
      Officers manage the list of kudos (like tags). Anyone can give each
      kudos to each person once a week. A kudos is anonymous: no author, a
      random id, sent a few minutes after you give it, kept 90 days. The
      once-a-week limit is kept by your own copy of the addon.
]]
local _, ns = ...
local D = ns.Data
local PF = {}
ns.Profile = PF

PF.ABOUT_MAX, PF.ABOUT_LINES = 300, 3
PF.STATUS_MAX = 80
PF.KUDOS_DAYS = 90
PF.KUDOS_COOLDOWN = 7 * 86400
PF.KUDOS_DELAY_MIN, PF.KUDOS_DELAY_MAX = 60, 300

local function Now() return ns.DB:Now() end
local function Me() return ns.PlayerFullName() end

------------------------------------------------------------------------
-- About me
------------------------------------------------------------------------
-- Line breaks travel as "\n" (two characters); messages can't carry real ones.
local function EncodeAbout(text)
    text = (text or ""):gsub("\r", "")
    local lines, out = 0, {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = ns.Trim(line):gsub("\\n", "/n")
        if lines <= PF.ABOUT_LINES then out[#out + 1] = line else out[#out] = out[#out] .. " " .. line end
        lines = lines + 1
    end
    while #out > 0 and out[#out] == "" do out[#out] = nil end
    return table.concat(out, "\\n"):sub(1, PF.ABOUT_MAX + 8)
end

function PF.DecodeAbout(v)
    return (v or ""):gsub("\\n", "\n")
end

-- { text, fromMain = name } for a member (an alt without one shows its main's).
function PF:About(full)
    local m = ns.DB:GetMember(full)
    if m and m.about then return PF.DecodeAbout(m.about) end
    local main = m and m.main
    local mm = main and ns.DB:GetMember(main)
    if mm and mm.about then return PF.DecodeAbout(mm.about), main end
    return nil
end

function PF:OwnAbout(full)
    local m = ns.DB:GetMember(full)
    return m and m.about and PF.DecodeAbout(m.about) or ""
end

function PF:SetAbout(text)
    local me = Me()
    if not (me and ns.DB:Guild()) then return nil, "You are not in a guild." end
    local v = EncodeAbout(ns.Trim(text or ""):sub(1, self.ABOUT_MAX))
    return ns.Sync:Set("AB:" .. me, v)
end

-- Officers can clear someone's About me (for anything inappropriate).
function PF:ClearAbout(full)
    if full ~= Me() and not ns.IsOfficer() then return nil, "Only officers can clear someone's About me." end
    return ns.Sync:Set("AB:" .. full, "")
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------
-- text, set time
function PF:Status(full)
    local m = ns.DB:GetMember(full)
    if m and m.status then return m.status, m.statusAt end
end

function PF:SetStatus(text)
    local me = Me()
    if not (me and ns.DB:Guild()) then return nil, "You are not in a guild." end
    text = ns.Trim((text or ""):gsub("[\r\n]+", " ")):sub(1, self.STATUS_MAX)
    return ns.Sync:Set("ST:" .. me, text)
end

------------------------------------------------------------------------
-- Usually online
-- Everything is kept in SERVER time (the same for the whole guild), as 168
-- hours from Monday 00:00. It's shown the way your own clock is set: the
-- game clock's "Use Local Time" and "24 Hour Mode" checkboxes. No time zones
-- are involved: local time is server time plus the difference between the
-- two clocks, which already includes daylight saving time.
--
-- Your hours come from:
--   learned   your own copy notes the server hour you're online every 10
--             minutes and keeps 4 weeks (settings.playLog[character]); an hour
--             counts once you've played it in 2 different weeks (1 at first)
--   by hand   per day: learned (default), not playing, or from-to (server time)
-- Shared as SC:<member> (42 hex digits, one bit per server hour).
------------------------------------------------------------------------
local HOURS = 168
PF.DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
PF.LEARN_DAYS = 28
PF.SAMPLE_EVERY = 600

-- Local time minus server time, in whole hours (e.g. -3), or nil when the
-- game doesn't give the server time.
function PF.LocalMinusServer()
    if not GetGameTime then return nil end
    local sh, sm = GetGameTime()
    if not sh then return nil end
    local t = date("*t")
    local diff = (t.hour * 60 + t.min) - (sh * 60 + (sm or 0))
    if diff > 12 * 60 then diff = diff - 24 * 60 elseif diff < -12 * 60 then diff = diff + 24 * 60 end
    return math.floor(diff / 60 + 0.5)
end

local function CVarBool(name)
    if C_CVar and C_CVar.GetCVarBool then
        local ok, v = pcall(C_CVar.GetCVarBool, name)
        if ok then return v end
    end
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, name)
        if ok then return v end
    end
    return nil
end

-- Follow the game clock: "local" or "server", and 24-hour mode.
function PF.ClockMode()
    local useLocal = CVarBool("timeMgrUseLocalTime") and PF.LocalMinusServer() ~= nil
    return useLocal and "local" or "server", CVarBool("timeMgrUseMilitaryTime") and true or false
end

-- "8 pm" / "20:00" (24 = midnight at the end of a day)
local function HourText(h)
    h = h % 24
    local _, mil = PF.ClockMode()
    if mil then return ("%02d:00"):format(h) end
    if h == 0 then return "12 am" end
    if h == 12 then return "12 pm" end
    return h < 12 and (h .. " am") or ((h - 12) .. " pm")
end
PF.HourText = HourText

-- Server time right now: weekday index (0 = Monday) and hour.
function PF.ServerNow()
    local off = PF.LocalMinusServer() or 0
    local t = date("*t", time() - off * 3600)
    return (t.wday + 5) % 7, t.hour, t
end

-- 168 booleans <-> 42 hex digits
local function Encode(bits)
    local out = {}
    for i = 0, HOURS / 4 - 1 do
        local n = 0
        for j = 0, 3 do if bits[i * 4 + j] then n = n + 2 ^ (3 - j) end end
        out[#out + 1] = ("%x"):format(n)
    end
    return table.concat(out)
end

local function Decode(hex)
    local bits = {}
    if not hex or #hex ~= HOURS / 4 then return bits end
    for i = 0, HOURS / 4 - 1 do
        local n = tonumber(hex:sub(i + 1, i + 1), 16) or 0
        for j = 0, 3 do bits[i * 4 + j] = math.floor(n / 2 ^ (3 - j)) % 2 == 1 end
    end
    return bits
end

-- Shifts hour bits by `offset` hours around the week.
local function Shift(bits, offset)
    local out = {}
    for h = 0, HOURS - 1 do
        if bits[h] then out[(h + offset) % HOURS] = true end
    end
    return out
end

local function MySchedule(create)
    local me = Me()
    if not me then return nil end
    local s = ns.DB:Settings()
    s.schedules = s.schedules or {}
    local mine = s.schedules[me]
    -- 1.13 beta stored a painted grid here; start over with the new kind
    if mine and mine.hours then mine = nil end
    if not mine and create then
        mine = { learn = true, days = {}, log = {} }
        s.schedules[me] = mine
    end
    return mine
end

function PF:LearnEnabled()
    local mine = MySchedule()
    return not mine or mine.learn ~= false
end

function PF:SetLearn(on)
    MySchedule(true).learn = on and true or false
    self:Publish()
end

-- Notes the current server hour (every 10 minutes while you play).
function PF:Sample()
    if not (ns.DB:Guild() and self:LearnEnabled()) then return end
    local mine = MySchedule(true)
    local day, hour, t = self.ServerNow()
    -- one sample per server hour per date
    local key = ("%04d%03d%02d"):format(t.year, t.yday, hour)
    local now = time()
    local changed = mine.log[key] == nil
    mine.log[key] = { t = now, slot = day * 24 + hour }
    for k, v in pairs(mine.log) do
        if type(v) ~= "table" or now - (v.t or 0) > self.LEARN_DAYS * 86400 then mine.log[k] = nil end
    end
    if changed then self:Publish() end
end

-- Learned hours: slot -> true, plus how many days of data there are.
function PF:LearnedHours()
    local mine = MySchedule()
    local bits, counts, oldest = {}, {}, nil
    if not mine then return bits, 0 end
    local now = time()
    for _, v in pairs(mine.log or {}) do
        counts[v.slot] = (counts[v.slot] or 0) + 1
        if not oldest or v.t < oldest then oldest = v.t end
    end
    local days = oldest and math.floor((now - oldest) / 86400) or 0
    local need = days >= 14 and 2 or 1
    for slot, n in pairs(counts) do
        if n >= need then bits[slot] = true end
    end
    return bits, days
end

-- Your per-day choices: day (0-6) -> nil (learned), "off", or { from, to } in server hours.
function PF:DayChoice(day)
    local mine = MySchedule()
    return mine and mine.days and mine.days[day]
end

function PF:SetDayChoice(day, choice)
    local mine = MySchedule(true)
    mine.days[day] = choice
    self:Publish()
end

-- Your hours in server time: learned, with your per-day choices on top.
function PF:MyServerHours()
    local learned = self:LearnEnabled() and self:LearnedHours() or {}
    local bits = {}
    for d = 0, 6 do
        local choice = self:DayChoice(d)
        if choice == "off" then
            -- nothing that day
        elseif type(choice) == "table" then
            local from, to = choice.from or 0, choice.to or 24
            if to <= from then to = to + 24 end -- past midnight
            for h = from, to - 1 do bits[(d * 24 + h) % HOURS] = true end
        else
            for h = 0, 23 do if learned[d * 24 + h] then bits[d * 24 + h] = true end end
        end
    end
    return bits
end

-- Shares your hours (only when they changed).
function PF:Publish()
    local me = Me()
    if not (me and ns.DB:Guild()) then return end
    local bits = self:MyServerHours()
    local any = next(bits) ~= nil
    local value = any and Encode(bits) or ""
    if (ns.Sync:Value("SC:" .. me) or "") == value then return true end
    return ns.Sync:Set("SC:" .. me, value)
end

-- A member's hours as your clock shows them: index -> true, or nil. mode:
-- "local" or "server" (default: follow the game clock).
function PF:Hours(full, mode)
    local m = ns.DB:GetMember(full)
    if not (m and m.schedule) then return nil end
    local bits = Decode(m.schedule)
    mode = mode or self.ClockMode()
    if mode == "local" then
        local off = self.LocalMinusServer()
        if off then bits = Shift(bits, off) end
    end
    return bits
end

-- Is the 2-hour block (day 0-6, block 0-11) on? (Either hour counts.)
function PF.BlockOn(bits, day, block)
    local h = day * 24 + block * 2
    return bits[h] or bits[h + 1] or false
end

-- "Mon-Fri 6 pm-12 am - Sat-Sun 2 pm-12 am"
function PF.Summary(bits)
    if not bits then return nil end
    local perDay = {}
    for d = 0, 6 do
        local ranges, h = {}, 0
        while h < 24 do
            if bits[d * 24 + h] then
                local s = h
                while h < 24 and bits[d * 24 + h] do h = h + 1 end
                ranges[#ranges + 1] = HourText(s) .. "-" .. HourText(h)
            else
                h = h + 1
            end
        end
        perDay[d] = table.concat(ranges, ", ")
    end
    local parts, d = {}, 0
    while d <= 6 do
        if perDay[d] == "" then
            d = d + 1
        else
            local s = d
            while d + 1 <= 6 and perDay[d + 1] == perDay[s] do d = d + 1 end
            local days = s == d and PF.DAYS[s + 1] or (PF.DAYS[s + 1] .. "-" .. PF.DAYS[d + 1])
            parts[#parts + 1] = days .. " " .. perDay[s]
            d = d + 1
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "  |cff6d6d6d-|r  ")
end

-- "(local time)" / "(server time)"
function PF.ClockLabel(mode)
    return (mode or PF.ClockMode()) == "local" and "local time" or "server time"
end

-- Is the member usually online right now?
function PF:UsuallyOnNow(full)
    local bits = self:Hours(full, "server")
    if not bits then return false end
    local day, hour = self.ServerNow()
    return bits[day * 24 + hour] or false
end

------------------------------------------------------------------------
-- Kudos types (officers manage them, like tags)
------------------------------------------------------------------------
-- All kudos types in order: { id, name, color, icon, order, retired }
function PF:KudosTypes(includeRetired)
    local DB = ns.DB
    local g = DB:Guild()
    if not g then return {} end
    if not (DB.kudosCache and DB.kudosCacheFor == g) then
        local list = {}
        for key, rec in pairs(ns.Sync:Store("guild")) do
            if key:sub(1, 3) == "KT:" then
                local k = ns.Sync.Codec.ParseKudosType(rec.v)
                if k then
                    k.id = key:sub(4)
                    list[#list + 1] = k
                end
            end
        end
        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name:lower() < b.name:lower()
        end)
        DB.kudosCache, DB.kudosCacheFor = list, g
    end
    if includeRetired then return DB.kudosCache end
    local out = {}
    for _, k in ipairs(DB.kudosCache) do if not k.retired then out[#out + 1] = k end end
    return out
end

function PF:KudosType(id)
    for _, k in ipairs(self:KudosTypes(true)) do if k.id == id then return k end end
end

local function SaveType(id, k)
    return ns.Sync:Set("KT:" .. id, ns.Sync.Codec.KudosType(k.color, k.order, k.retired, k.iconRaw or k.icon, k.name))
end

local function CleanName(name)
    name = ns.Trim(name or ""):gsub("[|\n\t;]", "")
    if name == "" then return nil, "Name it first." end
    if #name > D.MAX_TAG_LENGTH then return nil, ("Names are limited to %d characters."):format(D.MAX_TAG_LENGTH) end
    return name
end

function PF:CreateKudos(name, color, icon)
    if not ns.IsOfficer() then return nil, "Only officers can manage kudos." end
    local clean, err = CleanName(name)
    if not clean then return nil, err end
    local active = self:KudosTypes()
    if #active >= D.MAX_KUDOS then return nil, ("There can be up to %d kudos. Retire one first."):format(D.MAX_KUDOS) end
    for _, k in ipairs(self:KudosTypes(true)) do
        if k.name:lower() == clean:lower() then return nil, ("\"%s\" already exists."):format(clean) end
    end
    local all = self:KudosTypes(true)
    local order = (#all > 0 and all[#all].order or 0) + 10
    local id = "c" .. ns.Sync.Base36(Now()) .. ns.Sync.Base36(math.random(0, 1295))
    local ok, serr = SaveType(id, { color = color or 1, order = order, retired = false, icon = icon, name = clean })
    if not ok then return nil, serr end
    return self:KudosType(id)
end

function PF:UpdateKudos(id, name, color, icon)
    local k = self:KudosType(id)
    if not k then return nil, "Kudos not found." end
    local clean, err = CleanName(name)
    if not clean then return nil, err end
    for _, other in ipairs(self:KudosTypes(true)) do
        if other.id ~= id and other.name:lower() == clean:lower() then return nil, ("\"%s\" already exists."):format(clean) end
    end
    return SaveType(id, { color = color or k.color, order = k.order, retired = k.retired, icon = icon or k.icon, name = clean })
end

function PF:SetKudosRetired(id, retired)
    local k = self:KudosType(id)
    if not k then return nil, "Kudos not found." end
    if not retired and #self:KudosTypes() >= D.MAX_KUDOS then
        return nil, ("There can be up to %d kudos. Retire one first."):format(D.MAX_KUDOS)
    end
    return SaveType(id, { color = k.color, order = k.order, retired = retired, icon = k.icon, name = k.name })
end

function PF:MoveKudos(id, delta)
    local list = self:KudosTypes(true)
    for i, k in ipairs(list) do
        if k.id == id then
            local other = list[i + delta]
            if not other then return end
            local a, b = k.order, other.order
            if a == b then b = a + delta end
            SaveType(k.id, { color = k.color, order = b, retired = k.retired, icon = k.icon, name = k.name })
            return SaveType(other.id, { color = other.color, order = a, retired = other.retired, icon = other.icon, name = other.name })
        end
    end
end

function PF.KudosIcon(k)
    return k.icon or D.UNKNOWN_ICON
end

------------------------------------------------------------------------
-- Giving kudos (anonymous)
------------------------------------------------------------------------
-- { [typeId] = { count, last } } for a member over the last 90 days, plus total.
function PF:KudosFor(full)
    local out, total = {}, 0
    local store = ns.DB:Guild() and ns.Sync:Store("guild")
    if not store then return out, 0 end
    local prefix = "KU:" .. full .. ":"
    local cutoff = Now() - self.KUDOS_DAYS * 86400
    for key, rec in pairs(store) do
        if key:sub(1, #prefix) == prefix and rec.t >= cutoff then
            local typeId = key:sub(#prefix + 1):match("^([^:]+):")
            if typeId then
                local e = out[typeId] or { count = 0, last = 0 }
                e.count = e.count + 1
                if rec.t > e.last then e.last = rec.t end
                out[typeId] = e
                total = total + 1
            end
        end
    end
    -- kudos waiting to be sent count for you already
    for _, item in pairs(self:Outbox()) do
        if item.to == full then
            local e = out[item.type] or { count = 0, last = 0 }
            e.count = e.count + 1
            e.last = math.max(e.last, item.at)
            out[item.type] = e
            total = total + 1
        end
    end
    return out, total
end

-- Kudos types in order with their counts for a member (only ones they have).
function PF:KudosList(full)
    local counts = self:KudosFor(full)
    local list = {}
    for _, k in ipairs(self:KudosTypes(true)) do
        local c = counts[k.id]
        if c and c.count > 0 then list[#list + 1] = { type = k, count = c.count, last = c.last } end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.type.order < b.type.order
    end)
    return list
end

local function GivenTable()
    local s = ns.DB:Settings()
    s.kudosGiven = s.kudosGiven or {}
    local key = ns.DB:GuildKey() or "?"
    s.kudosGiven[key] = s.kudosGiven[key] or {}
    return s.kudosGiven[key]
end

-- Seconds until you may give `typeId` to `full` again (0 = now).
function PF:KudosWait(full, typeId)
    local given = GivenTable()[full]
    local last = given and given[typeId]
    if not last then return 0 end
    return math.max(0, last + self.KUDOS_COOLDOWN - Now())
end

function PF:CanGiveKudos(full)
    if not (full and ns.DB:Guild()) then return false end
    return full ~= Me()
end

function PF:Outbox()
    local g = ns.DB:Guild()
    if not g then return {} end
    g.kudosOutbox = g.kudosOutbox or {}
    return g.kudosOutbox
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function RandomId(n)
    local out = {}
    for i = 1, n do
        local d = math.random(0, 35)
        out[i] = B36:sub(d + 1, d + 1)
    end
    return table.concat(out)
end

function PF:GiveKudos(full, typeId)
    if not self:CanGiveKudos(full) then return nil, "You can't give yourself kudos." end
    local k = self:KudosType(typeId)
    if not k or k.retired then return nil, "That kudos isn't available." end
    local wait = self:KudosWait(full, typeId)
    if wait > 0 then
        return nil, ("You can give %s \"%s\" again in %s."):format(ns.ShortName(full), k.name, ns.Reviews.FormatWait(wait))
    end
    local now = Now()
    GivenTable()[full] = GivenTable()[full] or {}
    GivenTable()[full][typeId] = now
    -- sent a few minutes later, so when it shows up doesn't point at you
    self:Outbox()[RandomId(10)] = { to = full, type = typeId, at = now,
        sendAt = now + math.random(self.KUDOS_DELAY_MIN, self.KUDOS_DELAY_MAX) }
    ns:Fire("KUDOS_CHANGED")
    return true
end

-- Sends kudos whose time has come (no author, dated by the hour).
function PF:Pump()
    local g = ns.DB:Guild()
    if not (g and g.kudosOutbox and IsInGuild()) then return end
    local now = Now()
    for id, item in pairs(g.kudosOutbox) do
        if now >= item.sendAt then
            g.kudosOutbox[id] = nil
            local hour = math.floor(item.at / 3600) * 3600
            ns.Sync:Set(("KU:%s:%s:%s"):format(item.to, item.type, id), "1",
                { author = "", time = hour, noBatch = true, force = true })
        end
    end
end

function PF:Init()
    local function tick()
        PF:Pump()
        C_Timer.After(30, tick)
    end
    C_Timer.After(30, tick)
    -- learn when you play: note the server hour every 10 minutes
    local function sample()
        PF:Sample()
        C_Timer.After(PF.SAMPLE_EVERY, sample)
    end
    C_Timer.After(45, sample)
end
