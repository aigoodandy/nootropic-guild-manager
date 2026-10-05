--[[
    Nootropic Guild Manager - Guild stats
    Charts shown on the Polls tab like polls nobody votes on: each stat is a
    title and rows (a label, a count and a color), worked out from the roster
    by each copy of the addon. Nothing here is saved or synced.

    A stat:  { id, title, sub, total, rows = { { label, count, r, g, b,
               query (a roster search, optional), tip (optional) } },
               pctOf ("members" by default) }
]]
local _, ns = ...
local D = ns.Data
local ST = {}
ns.Stats = ST

-- Chart colors for stats without their own (tag palette, most distinct first)
local PALETTE = { 2, 1, 6, 4, 3, 5, 8, 9, 7, 10 }
local function Color(i)
    return D:TagColor(PALETTE[(i - 1) % #PALETTE + 1])
end

local function Row(label, count, r, g, b, query, tip)
    return { label = label, count = count, r = r, g = g, b = b, query = query, tip = tip }
end

local function Quote(s) return '"' .. s:lower() .. '"' end

local function Members() return ns.Roster.members or {} end

-- Sorts rows by count (most first), then by label.
local function ByCount(rows)
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return rows
end

local function Colorize(rows)
    for i, row in ipairs(rows) do
        if not row.r then row.r, row.g, row.b = Color(i) end
    end
    return rows
end

local function MembersSub(n)
    return n == 1 and "Live: 1 member" or ("Live: %d members"):format(n)
end

------------------------------------------------------------------------
-- The stats
------------------------------------------------------------------------
local BUILDERS = {}

BUILDERS.classes = function()
    local counts, files = {}, {}
    for _, e in ipairs(Members()) do
        if e.classFile ~= "" then
            counts[e.classFile] = (counts[e.classFile] or 0) + 1
            files[#files + 1] = e.classFile
        end
    end
    local rows = {}
    for file, n in pairs(counts) do
        local name = D:ClassName(file)
        local r, g, b = ns.ClassColor(file)
        rows[#rows + 1] = Row(name, n, r, g, b, "class:" .. Quote(name))
    end
    return { title = "What class is everyone?", rows = ByCount(rows), total = #Members(), sub = MembersSub(#Members()) }
end

BUILDERS.levels = function()
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local buckets = {}
    for _, e in ipairs(Members()) do
        local lv = e.level or 0
        if lv > 0 then
            local key = lv >= max and max or math.floor(lv / 10) * 10
            buckets[key] = (buckets[key] or 0) + 1
        end
    end
    local keys = {}
    for k in pairs(buckets) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a > b end) -- highest first
    local rows = {}
    for _, k in ipairs(keys) do
        local label, query
        if k == max then
            label, query = ("Level %d"):format(max), ("level>=%d"):format(max)
        else
            local lo, hi = math.max(1, k), math.min(k + 9, max - 1)
            label, query = ("%d-%d"):format(lo, hi), ("level>=%d level<=%d"):format(lo, hi)
        end
        rows[#rows + 1] = Row(label, buckets[k], nil, nil, nil, query)
    end
    return { title = "What level is everyone?", rows = Colorize(rows), total = #Members(), sub = MembersSub(#Members()) }
end

BUILDERS.ranks = function()
    local counts, index = {}, {}
    for _, e in ipairs(Members()) do
        local rank = e.rank ~= "" and e.rank or "?"
        counts[rank] = (counts[rank] or 0) + 1
        index[rank] = math.min(index[rank] or 99, e.rankIndex or 99)
    end
    local rows = {}
    for rank, n in pairs(counts) do
        rows[#rows + 1] = Row(rank, n, nil, nil, nil, "rank:" .. Quote(rank))
        rows[#rows].order = index[rank]
    end
    table.sort(rows, function(a, b) return a.order < b.order end) -- Guild Master first
    return { title = "Who holds which rank?", rows = Colorize(rows), total = #Members(), sub = MembersSub(#Members()) }
end

BUILDERS.professions = function()
    local counts, with = {}, 0
    for _, e in ipairs(Members()) do
        if e.profs and #e.profs > 0 then with = with + 1 end
        for _, p in ipairs(e.profs or {}) do
            if p.name and p.name ~= "" then counts[p.name] = (counts[p.name] or 0) + 1 end
        end
    end
    local rows = {}
    for name, n in pairs(counts) do
        rows[#rows + 1] = Row(name, n, nil, nil, nil, "prof:" .. Quote(name))
    end
    return {
        title = "Which professions do we have?",
        rows = Colorize(ByCount(rows)), total = #Members(),
        sub = ("Live: %d of %d members have a profession listed"):format(with, #Members()),
        note = "Percent of all members. Someone with two professions counts in both.",
    }
end

BUILDERS.mains = function()
    local mains, alts = 0, 0
    for _, e in ipairs(Members()) do
        if e.isAlt then alts = alts + 1 else mains = mains + 1 end
    end
    local rows = {
        Row("Mains", mains, nil, nil, nil, "is:main"),
        Row("Alts", alts, nil, nil, nil, "is:alt"),
    }
    return { title = "How many are alts?", rows = Colorize(rows), total = #Members(), sub = MembersSub(#Members()),
        note = "Alts are characters linked to a main on their profile." }
end

BUILDERS.addon = function()
    local users = 0
    for _, e in ipairs(Members()) do if e.hasAddon then users = users + 1 end end
    local rows = {
        Row("Using the addon", users, 0.25, 0.8, 0.35, "is:addon"),
        Row("Not using it", #Members() - users, 0.45, 0.45, 0.45, "-is:addon"),
    }
    return { title = "Who uses Nootropic Guild Manager?", rows = rows, total = #Members(), sub = MembersSub(#Members()) }
end

-- Usually-online hours for each person (alts merged into their main), as
-- your game clock shows them: person -> bits.
local function PeopleHours()
    local PF, people = ns.Profile, {}
    for _, e in ipairs(Members()) do
        local bits = PF:Hours(e.full)
        if bits and next(bits) then
            local who = e.main or e.full
            local merged = people[who] or {}
            for h, on in pairs(bits) do if on then merged[h] = true end end
            people[who] = merged
        end
    end
    local n = 0
    for _ in pairs(people) do n = n + 1 end
    return people, n
end

local function HoursSub(n)
    return ("Live: %d %s their usual hours (%s)"):format(n, n == 1 and "guildmate shares" or "guildmates share", ns.Profile.ClockLabel())
end

BUILDERS.days = function()
    local people, n = PeopleHours()
    local rows = {}
    for d = 0, 6 do
        local count = 0
        for _, bits in pairs(people) do
            for h = 0, 23 do
                if bits[d * 24 + h] then count = count + 1 break end
            end
        end
        rows[#rows + 1] = Row(ns.Profile.DAYS[d + 1], count)
    end
    return { title = "Which days is the guild online?", rows = Colorize(rows), total = n, pctOf = "people", sub = HoursSub(n),
        note = "From everyone's usual online hours (addon users). Alts count with their main." }
end

local TIMES = {
    { "Morning", 6, 12 },
    { "Afternoon", 12, 17 },
    { "Evening", 17, 22 },
    { "Late night", 22, 26 }, -- to 2 am
    { "Overnight", 2, 6 },
}

BUILDERS.times = function()
    local people, n = PeopleHours()
    local HourText = ns.Profile.HourText
    local rows = {}
    for _, t in ipairs(TIMES) do
        local label, from, to = t[1], t[2], t[3]
        local count = 0
        for _, bits in pairs(people) do
            local hit = false
            for d = 0, 6 do
                for h = from, to - 1 do
                    if bits[(d * 24 + h) % 168] then hit = true break end
                end
                if hit then break end
            end
            if hit then count = count + 1 end
        end
        rows[#rows + 1] = Row(label, count, nil, nil, nil, nil, ("%s to %s"):format(HourText(from), HourText(to)))
    end
    return { title = "What time is the guild online?", rows = Colorize(rows), total = n, pctOf = "people", sub = HoursSub(n),
        note = "From everyone's usual online hours (addon users), any day of the week." }
end

BUILDERS.kudos = function()
    local PF = ns.Profile
    local cutoff = ns.DB:Now() - PF.KUDOS_DAYS * 86400
    local byType, total = {}, 0
    for _, types in pairs(PF.KudosIndex()) do
        for typeId, times in pairs(types) do
            for _, t in ipairs(times) do
                if t >= cutoff then
                    byType[typeId] = (byType[typeId] or 0) + 1
                    total = total + 1
                end
            end
        end
    end
    local rows = {}
    for _, k in ipairs(PF:KudosTypes(true)) do
        local n = byType[k.id] or 0
        if n > 0 or not k.retired then
            local r, g, b = D:TagColor(k.color)
            rows[#rows + 1] = Row(k.name, n, r, g, b, nil, k.desc ~= "" and k.desc or nil)
        end
    end
    return { title = "Which kudos get given?", rows = ByCount(rows), total = total, pctOf = "kudos",
        sub = ("Live: %d kudos in the last %d days"):format(total, PF.KUDOS_DAYS) }
end

-- In list order.
ST.LIST = {
    { id = "classes",     name = "Classes" },
    { id = "levels",      name = "Levels" },
    { id = "ranks",       name = "Ranks" },
    { id = "professions", name = "Professions" },
    { id = "mains",       name = "Mains and alts" },
    { id = "addon",       name = "Addon users" },
    { id = "days",        name = "Busiest days" },
    { id = "times",       name = "Busiest times" },
    { id = "kudos",       name = "Kudos given" },
}

function ST:Name(id)
    for _, s in ipairs(self.LIST) do if s.id == id then return s.name end end
end

-- Works out a stat now.
function ST:Compute(id)
    local build = BUILDERS[id]
    if not build then return nil end
    local s = build()
    s.id = id
    s.pctOf = s.pctOf or "members"
    return s
end
