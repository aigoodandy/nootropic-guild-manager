--[[
    Nootropic Guild Manager - Guild stats
    Charts shown on the Polls tab like polls nobody votes on: each stat is a
    title and rows (a label, a count and a color), worked out from the roster
    by each copy of the addon. The built-in stats aren't saved or synced;
    custom stats (further down) save only their title, grouping and filters.

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
    local c = self:GetCustom(id)
    return c and c.title
end

------------------------------------------------------------------------
-- Custom stats: a title, what to count by, and filters (a roster search)
--
--   Everyone   SD:<id>  guild scope, officers make them
--   Officers   SO:<id>  officer scope, officers make them
--   Only me    saved in your own copy (guild.myStats), anyone makes them
-- Ids in the list: "c:<id>", "o:<id>", "m:<id>".
------------------------------------------------------------------------
ST.TITLE_MAX = 60
ST.FILTER_MAX = 120

-- What a custom stat can count by. keys(e) returns the member's values:
-- { label, query, r, g, b, order } (some members have several, some none).
local function KeyFor(label, query, r, g, b, order)
    return { label = label, query = query, r = r, g = g, b = b, order = order }
end

ST.GROUPS = {
    { key = "class", label = "Class", keys = function(e)
        if e.classFile == "" then return {} end
        local name = D:ClassName(e.classFile)
        local r, g, b = ns.ClassColor(e.classFile)
        return { KeyFor(name, "class:" .. Quote(name), r, g, b) }
    end },
    { key = "race", label = "Race", keys = function(e)
        if not e.race then return { KeyFor("Unknown") } end
        return { KeyFor(e.race, "race:" .. Quote(e.race)) }
    end },
    { key = "level", label = "Level range", keys = function(e)
        local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
        local lv = e.level or 0
        if lv >= max then return { KeyFor(("Level %d"):format(max), ("level>=%d"):format(max), nil, nil, nil, -max) } end
        local lo = math.floor(lv / 10) * 10
        local hi = math.min(lo + 9, max - 1)
        lo = math.max(1, lo)
        return { KeyFor(("%d-%d"):format(lo, hi), ("level>=%d level<=%d"):format(lo, hi), nil, nil, nil, -lo) }
    end },
    { key = "rank", label = "Rank", keys = function(e)
        local rank = e.rank ~= "" and e.rank or "?"
        return { KeyFor(rank, "rank:" .. Quote(rank), nil, nil, nil, e.rankIndex or 99) }
    end },
    { key = "prof", label = "Profession", keys = function(e)
        local out = {}
        for _, p in ipairs(e.profs or {}) do out[#out + 1] = KeyFor(p.name, "prof:" .. Quote(p.name)) end
        if #out == 0 then out[1] = KeyFor("None listed") end
        return out
    end },
    { key = "spec", label = "Specialization", keys = function(e)
        if not e.spec then return { KeyFor("Unknown") } end
        return { KeyFor(e.spec, "spec:" .. Quote(e.spec)) }
    end },
    { key = "kind", label = "Main or alt", keys = function(e)
        return { e.isAlt and KeyFor("Alts", "is:alt", nil, nil, nil, 2) or KeyFor("Mains", "is:main", nil, nil, nil, 1) }
    end },
    { key = "addon", label = "Uses the addon", keys = function(e)
        return { e.hasAddon and KeyFor("Using the addon", "is:addon", 0.25, 0.8, 0.35, 1)
            or KeyFor("Not using it", "-is:addon", 0.45, 0.45, 0.45, 2) }
    end },
    { key = "online", label = "Online now", keys = function(e)
        return { e.online and KeyFor("Online", "is:online", 0.25, 0.8, 0.35, 1)
            or KeyFor("Offline", "-is:online", 0.45, 0.45, 0.45, 2) }
    end },
    { key = "zone", label = "Zone", keys = function(e)
        if e.zone == "" then return { KeyFor("Unknown") } end
        return { KeyFor(e.zone, "zone:" .. Quote(e.zone)) }
    end },
    { key = "tag", label = "Tag", keys = function(e)
        local out = {}
        for _, tag in ipairs(e.tagList or {}) do
            local r, g, b = D:TagColor(tag.color)
            out[#out + 1] = KeyFor(tag.name, "tag:" .. Quote(tag.name), r, g, b)
        end
        if #out == 0 then out[1] = KeyFor("No tags") end
        return out
    end },
}

function ST:Group(key)
    for _, g in ipairs(self.GROUPS) do if g.key == key then return g end end
end

local SCOPES = { c = "SD", o = "SO" }
ST.VISIBILITY = {
    { key = "c", label = "Everyone in the guild", short = "everyone" },
    { key = "o", label = "Officers", short = "officers" },
    { key = "m", label = "Only me", short = "only you" },
}

local function MyStats()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.myStats = g.myStats or {}
    return g.myStats
end

-- Every custom stat you can see: { id = "c:xyz", vis = "c"|"o"|"m", title, group, filter }
function ST:Custom()
    local out = {}
    if not ns.DB:Guild() then return out end
    for vis, typ in pairs(SCOPES) do
        local store = ns.Sync:Store(typ == "SD" and "guild" or "officer")
        if store and (vis == "c" or ns.IsOfficer()) then
            for key, rec in pairs(store) do
                if key:sub(1, #typ + 1) == typ .. ":" then
                    local def = ns.Sync.Codec.ParseCustomStat(rec.v)
                    if def and not def.deleted then
                        def.id, def.vis, def.created = vis .. ":" .. key:sub(#typ + 2), vis, rec.t
                        out[#out + 1] = def
                    end
                end
            end
        end
    end
    for id, def in pairs(MyStats() or {}) do
        out[#out + 1] = { id = "m:" .. id, vis = "m", title = def.title, group = def.group, filter = def.filter, created = def.created or 0 }
    end
    table.sort(out, function(a, b)
        if a.vis ~= b.vis then return a.vis < b.vis end -- everyone, mine, officers
        return a.title:lower() < b.title:lower()
    end)
    return out
end

function ST:GetCustom(id)
    if type(id) ~= "string" or not id:find(":", 1, true) then return nil end
    for _, c in ipairs(self:Custom()) do if c.id == id then return c end end
end

function ST:CanEdit(c)
    return c.vis == "m" or ns.IsOfficer()
end

local function Clean(text, max)
    return ns.Trim(((text or ""):gsub("[|\r\n\t]+", " "))):sub(1, max)
end

-- Saves a custom stat (new when id is nil). Returns its id.
function ST:Save(id, title, group, filter, vis)
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    title, filter = Clean(title, self.TITLE_MAX), Clean(filter, self.FILTER_MAX)
    if title == "" then return nil, "Give it a title." end
    if not self:Group(group) then return nil, "Choose what to count by." end
    if vis ~= "m" and not ns.IsOfficer() then return nil, "Only officers can share stats. Choose Only me." end
    local old = id and self:GetCustom(id)
    if id and not old then return nil, "Stat not found." end
    if old and not self:CanEdit(old) then return nil, "Only officers can change shared stats." end
    -- moved to other viewers: remove the old one
    if old and old.vis ~= vis then
        local ok, err = self:Delete(id)
        if not ok then return nil, err end
        old = nil
    end
    local raw = old and id:sub(3) or (ns.Sync.Base36(ns.DB:Now()) .. ns.Sync.Base36(math.random(0, 1295)))
    if vis == "m" then
        local mine = MyStats()
        local prev = mine[raw]
        mine[raw] = { title = title, group = group, filter = filter, created = prev and prev.created or ns.DB:Now() }
        ns:Fire("STATS_CHANGED")
    else
        local ok, err = ns.Sync:Set(SCOPES[vis] .. ":" .. raw, ns.Sync.Codec.CustomStat(group, false, title, filter))
        if not ok then return nil, err end
    end
    return vis .. ":" .. raw
end

function ST:Delete(id)
    local c = self:GetCustom(id)
    if not c then return nil, "Stat not found." end
    if not self:CanEdit(c) then return nil, "Only officers can delete shared stats." end
    local raw = id:sub(3)
    if c.vis == "m" then
        MyStats()[raw] = nil
        ns:Fire("STATS_CHANGED")
        return true
    end
    return ns.Sync:Set(SCOPES[c.vis] .. ":" .. raw, ns.Sync.Codec.CustomStat(c.group, true, c.title, c.filter))
end

-- How many members a filter matches now.
function ST:MatchCount(filter)
    return #ns.Roster:Query(filter or ""), #Members()
end

local function ComputeCustom(c)
    local g = ST:Group(c.group)
    local members = ns.Roster:Query(c.filter or "")
    local rows, byLabel = {}, {}
    for _, e in ipairs(members) do
        for _, k in ipairs(g and g.keys(e) or {}) do
            local row = byLabel[k.label]
            if not row then
                local query = k.query and ns.Trim((c.filter or "") .. " " .. k.query) or nil
                row = Row(k.label, 0, k.r, k.g, k.b, query)
                row.order = k.order
                byLabel[k.label] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + 1
        end
    end
    -- in the group's own order (ranks, levels, mains first), else most first;
    -- "Unknown" and the like last
    table.sort(rows, function(a, b)
        local ua, ub = a.query == nil, b.query == nil
        if ua ~= ub then return ub end
        if a.order and b.order and a.order ~= b.order then return a.order < b.order end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    Colorize(rows)
    for _, row in ipairs(rows) do
        if not row.query then row.r, row.g, row.b = 0.5, 0.5, 0.5 end
    end
    local filterText = (c.filter or "") ~= "" and ("  |cff9d9d9dFilters: %s|r"):format(c.filter) or ""
    local vis
    for _, v in ipairs(ST.VISIBILITY) do if v.key == c.vis then vis = v.label end end
    return {
        title = c.title, rows = rows, total = #members,
        sub = (#members == 1 and "Live: 1 member" or ("Live: %d members"):format(#members)) .. filterText,
        note = ("Seen by: %s. Counted by %s.%s"):format(vis or "?", g and g.label:lower() or "?",
            (g and (g.key == "prof" or g.key == "tag")) and " Someone with several counts in each." or ""),
        custom = c,
    }
end

-- Works out a stat now (a built-in id like "classes", or a custom "c:..." id).
function ST:Compute(id)
    local s
    if BUILDERS[id] then
        s = BUILDERS[id]()
    else
        local c = self:GetCustom(id)
        if not c then return nil end
        s = ComputeCustom(c)
    end
    s.id = id
    s.pctOf = s.pctOf or "members"
    return s
end
