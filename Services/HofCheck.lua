--[[
    Nootropic Guild Manager - Checking Hall of Fame numbers
    The game lets you compare statistics with a player you inspect (the
    achievement comparison: SetAchievementComparisonUnit, then
    GetComparisonStatistic once INSPECT_ACHIEVEMENT_READY fires). When an
    officer inspects a guildmate, their copy quietly reads that guildmate's
    real statistics and compares them with what the guildmate's addon shares.

      HC:<member> = "<time>;ok"                                  numbers match
      HC:<member> = "<time>;bad;quests=900/150,kills=..."        claimed/real

    Officers only (they're the ones who can act on it, and it keeps requests
    to the game rare): written by the officer who checked, sent only on the
    officer channel (other members never receive it), shown to officers in
    tooltips. Nothing happens automatically: an officer decides whether to
    Hide from Hall of Fame. Shared numbers can be a few minutes behind the
    game, so only claims above the real number (plus a small margin) count.
    Each guildmate is checked at most every 6 hours, and only when you
    inspect them yourself.
]]
local _, ns = ...
local CK = {}
ns.HofCheck = CK

CK.EVERY = 6 * 3600
CK.WAIT = 10 -- seconds to wait for the game's answer

CK.last = {}     -- member -> GetTime() of our last request
CK.pending = nil -- { guid, full, at }

function CK:Available()
    return type(SetAchievementComparisonUnit) == "function" and type(GetComparisonStatistic) == "function"
end

local function UnitFor(guid)
    local units = { "target", "mouseover", "focus" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for _, u in ipairs(units) do
        local ok, g = pcall(UnitGUID, u)
        if ok and g == guid then return u end
    end
end

local function ReadComparison(id)
    local ok, raw = pcall(GetComparisonStatistic, id)
    if not ok then return nil end
    if issecretvalue and issecretvalue(raw) then return nil end
    return ns.HallOfFame.Parse(raw)
end

-- The real numbers from the game's comparison: { key = n }.
function CK:ReadReal()
    local HF, out = ns.HallOfFame, {}
    for _, s in ipairs(HF.STATS) do
        local n
        if s.id then
            n = ReadComparison(s.id)
        elseif s.key == "bosses" then
            for _, id in ipairs(HF.BOSS_IDS) do
                local v = ReadComparison(id)
                if v then n = (n or 0) + v end
            end
        end
        if n then out[s.key] = n end
    end
    return out
end

-- Compares claimed (their shared all-time numbers) with real: the value to
-- share ("ok" or "bad;key=claimed/real,...").
function CK.Compare(claimed, real)
    local bad = {}
    for _, s in ipairs(ns.HallOfFame.STATS) do
        local c, r = claimed[s.key], real[s.key]
        if c and r then
            local margin = math.max(3, math.ceil(r * 0.02))
            if c > r + margin then bad[#bad + 1] = ("%s=%d/%d"):format(s.key, c, r) end
        end
    end
    if #bad == 0 then return "ok" end
    return "bad;" .. table.concat(bad, ",")
end

-- Asks the game for `e`'s statistics if they're worth checking now.
function CK:Request(e, unit)
    if not (self:Available() and ns.IsOfficer() and e and not e.isSelf) then return false end
    if not ns.Sync:Value("HF:" .. e.full) then return false end -- nothing shared to check
    local now = GetTime()
    if self.last[e.full] and now - self.last[e.full] < self.EVERY then return false end
    if self.pending and now - self.pending.at < self.WAIT then return false end
    -- the achievement window may be comparing someone: leave it alone
    if AchievementFrame and AchievementFrame:IsShown() then return false end
    local ok = pcall(SetAchievementComparisonUnit, unit)
    if not ok then return false end
    self.last[e.full] = now
    self.pending = { guid = e.guid, full = e.full, at = now }
    return true
end

function CK:OnInspectReady(guid)
    local e = guid and ns.Roster.byGuid and ns.Roster.byGuid[guid]
    if not e then return end
    local unit = UnitFor(guid)
    if unit then self:Request(e, unit) end
end

function CK:OnComparisonReady(guid)
    local p = self.pending
    if not p or (guid and guid ~= p.guid) then return end
    self.pending = nil
    local real = self:ReadReal()
    pcall(ClearAchievementComparisonUnit)
    if not next(real) then return end
    local r = ns.HallOfFame.Decode(ns.Sync:Value("HF:" .. p.full))
    if not r then return end
    local verdict = CK.Compare(r.all, real)
    ns.Sync:Set("HC:" .. p.full, tostring(ns.DB:Now()) .. ";" .. verdict)
end

-- { t, by, ok, bad = { { key, claimed, real }... } } or nil.
function CK:Result(full)
    local rec = full and ns.Sync:Get("HC:" .. full)
    if not rec or (rec.v or "") == "" then return nil end
    local t, verdict, rest = rec.v:match("^(%d+);(%a+);?(.*)$")
    if not t then return nil end
    local out = { t = tonumber(t), by = rec.a, ok = verdict == "ok", bad = {} }
    for k, c, r in (rest or ""):gmatch("(%w+)=(%d+)/(%d+)") do
        out.bad[#out.bad + 1] = { key = k, claimed = tonumber(c), real = tonumber(r) }
    end
    return out
end

-- A tooltip line for officers, or nil.
function CK:TooltipLine(full)
    if not ns.IsOfficer() then return nil end
    local res = self:Result(full)
    if not res then return nil end
    local when = ns.FormatAgo(res.t)
    if res.ok then
        return ("|cff40c040Hall of Fame numbers checked %s: they match the game.|r"):format(when)
    end
    local parts = {}
    for _, b in ipairs(res.bad) do
        local s = ns.HallOfFame.BY_KEY[b.key]
        parts[#parts + 1] = ("%s %d (game: %d)"):format(s and s.label or b.key, b.claimed, b.real)
    end
    return ("|cffff2020Hall of Fame numbers don't match the game|r (checked %s by %s): %s"):format(
        when, ns.ShortName(res.by or "?"), table.concat(parts, ", "))
end

function CK:Init()
    ns:RegisterEvent("INSPECT_READY", function(_, guid) CK:OnInspectReady(guid) end)
    ns:RegisterEvent("INSPECT_ACHIEVEMENT_READY", function(_, guid) CK:OnComparisonReady(guid) end)
end
