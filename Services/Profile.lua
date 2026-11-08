--[[
    Nootropic Guild Manager - Profile extras
    Contact info and usual online hours.

    Contact (CN:<member>)
      Discord name (up to 32 characters) and a contact note (up to 80:
      BattleTag, timezone, "DM me before raids"...). Set by the member or
      ranks allowed to edit other profiles (for guildmates without the
      addon). An alt without one shows its main's.

    Usually online (SC:<member>)
      Learned from when you actually play (your own copy notes it, last 4
      weeks; Options can turn it off). Kept and shared in server time; shown
      in local or server time the way your game clock is set.
]]
local _, ns = ...
local PF = {}
ns.Profile = PF

PF.DISCORD_MAX = 32
PF.CONTACT_NOTE_MAX = 80

local function Me() return ns.PlayerFullName() end

------------------------------------------------------------------------
-- Contact (CN:<member> = "discord;note")
------------------------------------------------------------------------
local function ParseContact(v)
    if not v or v == "" then return "", "" end
    local discord, note = v:match("^([^;]*);(.*)$")
    if not discord then return v, "" end
    return discord, note
end

-- discord, note (each "" when empty) a member set, without their main's.
function PF:OwnContact(full)
    local m = ns.DB:GetMember(full)
    return ParseContact(m and m.contact)
end

-- discord, note, fromMain: an alt without its own shows its main's.
-- Returns nil when neither has one.
function PF:Contact(full)
    local d, n = self:OwnContact(full)
    if d ~= "" or n ~= "" then return d, n end
    local m = ns.DB:GetMember(full)
    local main = m and m.main
    if main then
        d, n = self:OwnContact(main)
        if d ~= "" or n ~= "" then return d, n, main end
    end
    return nil
end

function PF:CanEditContact(full)
    return full ~= nil and ns.Sync:CanWrite("CN:" .. full)
end

-- Either value may be nil to keep what's there.
function PF:SetContact(full, discord, note)
    if not (full and ns.DB:Guild()) then return nil, "You are not in a guild." end
    if not self:CanEditContact(full) then return nil, "Only officers can change someone else's contact info." end
    local curD, curN = self:OwnContact(full)
    discord = discord == nil and curD or ns.Trim((discord:gsub("[;\r\n]", ""))):sub(1, self.DISCORD_MAX)
    note = note == nil and curN or ns.Trim((note:gsub("[\r\n]+", " "))):sub(1, self.CONTACT_NOTE_MAX)
    local v = (discord == "" and note == "") and "" or (discord .. ";" .. note)
    return ns.Sync:Set("CN:" .. full, v)
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
        mine = { learn = true, log = {} }
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

-- Your hours in server time (learned), or none while learning is off.
function PF:MyServerHours()
    if not self:LearnEnabled() then return {} end
    return (self:LearnedHours())
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


function PF:Init()
    -- learn when you play: note the server hour every 10 minutes
    local function sample()
        PF:Sample()
        C_Timer.After(PF.SAMPLE_EVERY, sample)
    end
    C_Timer.After(45, sample)
end
