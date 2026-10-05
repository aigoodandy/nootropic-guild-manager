--[[
    Nootropic Guild Manager - Guild goals
    A goal counts the guildmates its filters match (a roster search, like a
    stat's) against a target: "10 level 60 mains for Molten Core". It can
    have parts, smaller targets among those members ("2 tanks": role:tank),
    and a target date. Progress is worked out live by each copy of the
    addon; only the goal itself is saved.

    Who sees a goal, like stats:
      Guild-wide    GD:<id>  guild scope, officers make and edit them
      Officers      GO:<id>  officer scope, officers make and edit them
      Only me       saved in your own copy (guild.myGoals), anyone
    Ids in the list: "c:<id>", "o:<id>", "m:<id>".
]]
local _, ns = ...
local GL = {}
ns.Goals = GL

GL.TITLE_MAX = 60
GL.FILTER_MAX = 120
GL.DESC_MAX = 200
GL.MAX_PARTS = 4
GL.MAX_TARGET = 999
GL.ALMOST_LEVELS = 5 -- "almost there" for level goals: this many levels short

-- Launch day of World of Warcraft Forever: November 5, 2026, 00:00 UTC (a
-- fixed number, the same on every copy, so the built-in goal is identical
-- everywhere). "End of launch week" is 7 days later: the end of Nov 11 UTC.
GL.LAUNCH_TIME = 1793836800

-- Goals every guild starts with (GD:d1..), like the default stats; officers
-- can change or delete them. title, filter, target, days after launch it's due
GL.DEFAULTS = {
    { "10 level 20s by the end of launch week", "level>=20", 10, 7 },
}

function GL.DefaultGoal(i)
    local def = GL.DEFAULTS[i]
    if not def then return nil end
    return { title = def[1], filter = def[2], target = def[3], parts = {},
        due = GL.LAUNCH_TIME and (GL.LAUNCH_TIME + def[4] * 86400) or nil }
end

local SCOPES = { c = "GD", o = "GO" }

local function MyGoals()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.myGoals = g.myGoals or {}
    return g.myGoals
end

-- Every goal you can see: { id, vis, title, desc, target, due, parts, filter }
function GL:All()
    local out = {}
    if not ns.DB:Guild() then return out end
    for vis, typ in pairs(SCOPES) do
        local store = ns.Sync:Store(typ == "GD" and "guild" or "officer")
        if store and (vis == "c" or ns.IsOfficer()) then
            for key, rec in pairs(store) do
                if key:sub(1, #typ + 1) == typ .. ":" then
                    local def = ns.Sync.Codec.ParseGoal(rec.v)
                    if def and not def.deleted then
                        def.id, def.vis = vis .. ":" .. key:sub(#typ + 2), vis
                        out[#out + 1] = def
                    end
                end
            end
        end
    end
    for raw, def in pairs(MyGoals() or {}) do
        out[#out + 1] = { id = "m:" .. raw, vis = "m", title = def.title, desc = def.desc, target = def.target,
            due = def.due, parts = def.parts or {}, filter = def.filter }
    end
    table.sort(out, function(a, b)
        if a.vis ~= b.vis then return a.vis < b.vis end -- guild-wide, mine, officers
        return a.title:lower() < b.title:lower()
    end)
    return out
end

function GL:Get(id)
    if type(id) ~= "string" then return nil end
    for _, g in ipairs(self:All()) do if g.id == id then return g end end
end

function GL:CanEdit(g)
    return g.vis == "m" or ns.IsOfficer()
end

local function Clean(text, max)
    return ns.Trim(((text or ""):gsub("[|\r\n\t]+", " "))):sub(1, max)
end

-- def: { title, desc, filter, target, due, parts = { { label, need, filter } }, vis }
-- Saves a goal (new when id is nil). Returns its id.
function GL:Save(id, def)
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    local title, filter = Clean(def.title, self.TITLE_MAX), Clean(def.filter, self.FILTER_MAX)
    if title == "" then return nil, "Give it a title." end
    local target = math.floor(tonumber(def.target) or 0)
    if target < 1 or target > self.MAX_TARGET then return nil, ("Set a target from 1 to %d members."):format(self.MAX_TARGET) end
    local vis = def.vis
    if vis ~= "m" and not ns.IsOfficer() then return nil, "Only officers can share goals. Choose Only me." end
    local parts = {}
    for _, p in ipairs(def.parts or {}) do
        local label, need = Clean(p.label, 24), math.floor(tonumber(p.need) or 0)
        local pf = Clean(p.filter, self.FILTER_MAX)
        if label ~= "" or pf ~= "" then
            if label == "" then return nil, "Give each part a name." end
            if pf == "" then return nil, ("Give \"%s\" a filter, like role:tank."):format(label) end
            if need < 1 then return nil, ("Set how many \"%s\" are needed."):format(label) end
            parts[#parts + 1] = { label = label, need = need, filter = pf }
        end
    end
    local old = id and self:Get(id)
    if id and not old then return nil, "Goal not found." end
    if old and not self:CanEdit(old) then return nil, "Only officers can change shared goals." end
    local raw = old and id:sub(3)
    if old and old.vis ~= vis then
        local ok, err = self:Delete(id)
        if not ok then return nil, err end
        raw = nil
    end
    raw = raw or (ns.Sync.Base36(ns.DB:Now()) .. ns.Sync.Base36(math.random(0, 1295)))
    local due = tonumber(def.due)
    local desc = Clean(def.desc, self.DESC_MAX)
    local g = { title = title, desc = desc ~= "" and desc or nil, filter = filter, target = target, due = due, parts = parts }
    if vis == "m" then
        MyGoals()[raw] = g
        ns:Fire("STATS_CHANGED")
    else
        local ok, err = ns.Sync:Set(SCOPES[vis] .. ":" .. raw, ns.Sync.Codec.Goal(g))
        if not ok then return nil, err end
    end
    return vis .. ":" .. raw
end

function GL:Delete(id)
    local g = self:Get(id)
    if not g then return nil, "Goal not found." end
    if not self:CanEdit(g) then return nil, "Only officers can delete shared goals." end
    local raw = id:sub(3)
    if g.vis == "m" then
        MyGoals()[raw] = nil
        ns:Fire("STATS_CHANGED")
        return true
    end
    g.deleted = true
    return ns.Sync:Set(SCOPES[g.vis] .. ":" .. raw, ns.Sync.Codec.Goal(g))
end

------------------------------------------------------------------------
-- Progress
------------------------------------------------------------------------
local function Join(a, b)
    return ns.Trim((a or "") .. " " .. (b or ""))
end

-- For a level goal ("level>=60"), the members a few levels short of it.
local function Almost(filter)
    local lv = tonumber((filter or ""):match("level>=(%d+)"))
    if not lv or lv <= 1 then return nil end
    local lo = math.max(1, lv - GL.ALMOST_LEVELS)
    local f = filter:gsub("level>=%d+", ("level>=%d level<%d"):format(lo, lv), 1)
    return ns.Roster:Query(f), lo
end

local function ByName(a, b) return a.short < b.short end

-- { goal, count, target, pct, done, members, parts = { { label, count, need, done } },
--   almost (members, or nil), almostFrom }
function GL:Progress(id)
    local g = self:Get(id)
    if not g then return nil end
    local members = ns.Roster:Query(g.filter or "")
    table.sort(members, ByName)
    local p = { goal = g, count = #members, target = g.target, members = members, parts = {} }
    p.pct = math.min(100, math.floor(#members * 100 / math.max(1, g.target) + 0.5))
    p.done = #members >= g.target
    for _, part in ipairs(g.parts) do
        local n = #ns.Roster:Query(Join(g.filter, part.filter))
        p.parts[#p.parts + 1] = { label = part.label, filter = part.filter, count = n, need = part.need, done = n >= part.need }
    end
    local almost, from = Almost(g.filter)
    if almost then
        table.sort(almost, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            return a.short < b.short
        end)
        p.almost, p.almostFrom = almost, from
    end
    return p
end

-- "60%" for the list
function GL:Percent(id)
    local p = self:Progress(id)
    return p and p.pct or 0, p and p.done
end
