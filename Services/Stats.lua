--[[
    Nootropic Guild Manager - Guild stats
    Charts shown on the Insights tab like polls nobody votes on. A stat is a
    title, what to count by (class, race, level...) and optional filters (a
    roster search). Its rows (a label, a count and a color) are worked out
    live from the roster by each copy of the addon; only the stat's title,
    grouping and filters are saved.

    Who sees a stat:
      Guild Stats   SD:<id>  guild scope, officers make and edit them
      Officers      SO:<id>  officer scope, officers make and edit them
      My Stats      saved in your own copy (guild.myStats), anyone
    Ids in the list: "c:<id>", "o:<id>", "m:<id>".

    Nine Guild Stats come with the addon (SD:d1..d9, the same on every copy,
    like the default tags), and officers can change or delete them too.

    A computed stat: { id, title, sub, total, pctOf, note, rows = { { label,
      count, r, g, b, query (a roster search, optional), tip (optional) } } }
]]
local _, ns = ...
local D = ns.Data
local ST = {}
ns.Stats = ST

ST.TITLE_MAX = 60
ST.FILTER_MAX = 120

-- Chart colors for rows without their own (tag palette, most distinct first)
local PALETTE = { 2, 1, 6, 4, 3, 5, 8, 9, 7, 10 }
local function Color(i)
    return D:TagColor(PALETTE[(i - 1) % #PALETTE + 1])
end

local function Row(label, count, r, g, b, query, tip)
    return { label = label, count = count, r = r, g = g, b = b, query = query, tip = tip }
end

local function Quote(s) return '"' .. s:lower() .. '"' end

local function Members() return ns.Roster.members or {} end

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
-- What a stat can count by
--   keys(e)  the member's values { label, query, r, g, b, order, icon,
--            classFile } (several for professions and tags; rows count
--            members). icon / classFile: the row's own icon, if it has one.
--   compute(members)  for counts that aren't one member per row: returns
--            rows, total, pctOf, sub
------------------------------------------------------------------------
local function KeyFor(label, query, r, g, b, order, icon)
    return { label = label, query = query, r = r, g = g, b = b, order = order, icon = icon }
end

-- Usually-online hours for each person among `members` (alts merged into
-- their main), as your game clock shows them: person -> bits.
local function PeopleHours(members)
    local PF, people = ns.Profile, {}
    for _, e in ipairs(members) do
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

local TIMES = {
    { "Morning", 6, 12 },
    { "Afternoon", 12, 17 },
    { "Evening", 17, 22 },
    { "Late night", 22, 26 }, -- to 2 am
    { "Overnight", 2, 6 },
}

ST.GROUPS = {
    { key = "class", label = "Class", keys = function(e)
        if e.classFile == "" then return {} end
        local name = D:ClassName(e.classFile)
        local r, g, b = ns.ClassColor(e.classFile)
        local k = KeyFor(name, "class:" .. Quote(name), r, g, b)
        k.classFile = e.classFile
        return { k }
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
    { key = "prof", label = "Profession", multi = true, keys = function(e)
        local out = {}
        for _, p in ipairs(e.profs or {}) do
            out[#out + 1] = KeyFor(p.name, "prof:" .. Quote(p.name), nil, nil, nil, nil, D:ProfIcon(p))
        end
        if #out == 0 then out[1] = KeyFor("None listed") end
        return out
    end },
    { key = "spec", label = "Specialization", keys = function(e)
        if not e.spec then return { KeyFor("Unknown") } end
        return { KeyFor(e.spec, "spec:" .. Quote(e.spec)) }
    end },
    { key = "role", label = "Role", multi = true, keys = function(e)
        local out = {}
        for i, r in ipairs(D.ROLES) do
            if e.roles and e.roles[r.key] then
                out[#out + 1] = KeyFor(r.label, "role:" .. r.key, r.color[1], r.color[2], r.color[3], i, r.icon)
            end
        end
        if #out == 0 then out[1] = KeyFor("Not set") end
        return out
    end },
    { key = "kind", label = "Main or alt", note = "Alts are characters linked to a main on their profile.", keys = function(e)
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
    { key = "tag", label = "Tag", multi = true, keys = function(e)
        local out = {}
        for _, tag in ipairs(e.tagList or {}) do
            local r, g, b = D:TagColor(tag.color)
            out[#out + 1] = KeyFor(tag.name, "tag:" .. Quote(tag.name), r, g, b, nil, D:TagIcon(tag))
        end
        if #out == 0 then out[1] = KeyFor("No tags") end
        return out
    end },
    { key = "day", label = "Busiest days",
        note = "From usual online hours (addon users). Alts count with their main.",
        compute = function(members)
            local people, n = PeopleHours(members)
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
            return Colorize(rows), n, "people", HoursSub(n)
        end },
    { key = "time", label = "Busiest times",
        note = "From usual online hours (addon users), any day of the week.",
        compute = function(members)
            local people, n = PeopleHours(members)
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
            return Colorize(rows), n, "people", HoursSub(n)
        end },
    { key = "kudos", label = "Kudos received",
        note = "Kudos the matching members received in the last 90 days.",
        compute = function(members)
            local PF = ns.Profile
            local cutoff = ns.DB:Now() - PF.KUDOS_DAYS * 86400
            local index, byType, total = PF.KudosIndex(), {}, 0
            for _, e in ipairs(members) do
                for typeId, times in pairs(index[e.full] or {}) do
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
                    rows[#rows].icon = PF.KudosIcon(k)
                end
            end
            table.sort(rows, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.label < b.label
            end)
            return rows, total, "kudos", ("Live: %d kudos in the last %d days"):format(total, PF.KUDOS_DAYS)
        end },
}

function ST:Group(key)
    for _, g in ipairs(self.GROUPS) do if g.key == key then return g end end
end

------------------------------------------------------------------------
-- The stats that come with the addon (SD:d1..d9): title, count by, layout
------------------------------------------------------------------------
ST.DEFAULTS = {
    { "What class is everyone?",           "class", "pie" },
    { "What level is everyone?",           "level", "columns" },
    { "Who holds which rank?",             "rank",  "bars" },
    { "Which professions do we have?",     "prof",  "bars" },
    { "How many are alts?",                "kind",  "number" },
    { "Who uses Nootropic Guild Manager?", "addon", "number" },
    { "Which days is the guild online?",   "day",   "columns" },
    { "What time is the guild online?",    "time",  "columns" },
    { "Which kudos get given?",            "kudos", "barspie" },
}

------------------------------------------------------------------------
-- Saved stats
------------------------------------------------------------------------
local SCOPES = { c = "SD", o = "SO" }
-- In list order.
ST.VISIBILITY = {
    { key = "c", label = "Everyone in the guild", section = "Guild Stats" },
    { key = "o", label = "Officers",              section = "Officers" },
    { key = "m", label = "Only me",               section = "My Stats" },
}

local function MyStats()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.myStats = g.myStats or {}
    return g.myStats
end

-- Built-in ones first (in their order), then by title.
local function SortKey(raw)
    return tonumber(raw:match("^d(%d+)$")) or 1000
end

-- Every stat you can see: { id = "c:xyz", vis = "c"|"o"|"m", title, group,
-- filter, looks = { [row label] = { color, icon } } }
function ST:All()
    local out = {}
    if not ns.DB:Guild() then return out end
    for vis, typ in pairs(SCOPES) do
        local store = ns.Sync:Store(typ == "SD" and "guild" or "officer")
        if store and (vis == "c" or ns.IsOfficer()) then
            for key, rec in pairs(store) do
                if key:sub(1, #typ + 1) == typ .. ":" then
                    local def = ns.Sync.Codec.ParseCustomStat(rec.v)
                    if def and not def.deleted and self:Group(def.group) then
                        local raw = key:sub(#typ + 2)
                        def.id, def.vis, def.sort = vis .. ":" .. raw, vis, SortKey(raw)
                        out[#out + 1] = def
                    end
                end
            end
        end
    end
    for raw, def in pairs(MyStats() or {}) do
        if self:Group(def.group) then
            out[#out + 1] = { id = "m:" .. raw, vis = "m", title = def.title, group = def.group, filter = def.filter,
                looks = def.looks or {}, layout = def.layout, sort = SortKey(raw) }
        end
    end
    table.sort(out, function(a, b)
        if a.vis ~= b.vis then return a.vis < b.vis end
        if a.sort ~= b.sort then return a.sort < b.sort end
        return a.title:lower() < b.title:lower()
    end)
    return out
end

function ST:Get(id)
    if type(id) ~= "string" or not id:find(":", 1, true) then return nil end
    for _, c in ipairs(self:All()) do if c.id == id then return c end end
end

function ST:Name(id)
    local c = self:Get(id)
    return c and c.title
end

function ST:CanEdit(c)
    return c.vis == "m" or ns.IsOfficer()
end

local function Clean(text, max)
    return ns.Trim(((text or ""):gsub("[|\r\n\t]+", " "))):sub(1, max)
end

-- Only looks that differ from a row's own (so new rows keep theirs).
local function TrimLooks(looks)
    local out = {}
    for label, l in pairs(looks or {}) do
        if l.color or l.icon ~= nil then out[ns.Sync.Codec.LookLabel(label)] = { color = l.color, icon = l.icon } end
    end
    return out
end

-- Saves a stat (new when id is nil). looks: each row's color and icon.
-- Returns its id.
function ST:Save(id, title, group, filter, vis, looks, layout)
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    title, filter = Clean(title, self.TITLE_MAX), Clean(filter, self.FILTER_MAX)
    if title == "" then return nil, "Give it a title." end
    if not self:Group(group) then return nil, "Choose what to count by." end
    if vis ~= "m" and not ns.IsOfficer() then return nil, "Only officers can share stats. Choose Only me." end
    local old = id and self:Get(id)
    if id and not old then return nil, "Stat not found." end
    if old and not self:CanEdit(old) then return nil, "Only officers can change shared stats." end
    local raw = old and id:sub(3)
    -- moved to other viewers: remove the old one (a built-in keeps its place)
    if old and old.vis ~= vis then
        local ok, err = self:Delete(id)
        if not ok then return nil, err end
        if not raw:match("^d%d+$") then raw = nil end
    end
    raw = raw or (ns.Sync.Base36(ns.DB:Now()) .. ns.Sync.Base36(math.random(0, 1295)))
    looks = TrimLooks(looks or (old and old.looks))
    layout = layout or (old and old.layout)
    if vis == "m" then
        MyStats()[raw] = { title = title, group = group, filter = filter, looks = looks, layout = layout }
        ns:Fire("STATS_CHANGED")
    else
        local ok, err = ns.Sync:Set(SCOPES[vis] .. ":" .. raw, ns.Sync.Codec.CustomStat({
            group = group, title = title, filter = filter, looks = looks, layout = layout }))
        if not ok then return nil, err end
    end
    return vis .. ":" .. raw
end

function ST:Delete(id)
    local c = self:Get(id)
    if not c then return nil, "Stat not found." end
    if not self:CanEdit(c) then return nil, "Only officers can delete shared stats." end
    local raw = id:sub(3)
    if c.vis == "m" then
        MyStats()[raw] = nil
        ns:Fire("STATS_CHANGED")
        return true
    end
    return ns.Sync:Set(SCOPES[c.vis] .. ":" .. raw, ns.Sync.Codec.CustomStat({
        group = c.group, deleted = true, title = c.title, filter = c.filter, looks = c.looks, layout = c.layout }))
end

-- How many members a filter matches now.
function ST:MatchCount(filter)
    return #ns.Roster:Query(filter or ""), #Members()
end

------------------------------------------------------------------------
-- Working a stat out
------------------------------------------------------------------------
-- Rows counting members by the group's keys.
local function CountMembers(g, members, filter)
    local rows, byLabel = {}, {}
    for _, e in ipairs(members) do
        for _, k in ipairs(g.keys(e)) do
            local row = byLabel[k.label]
            if not row then
                local query = k.query and ns.Trim((filter or "") .. " " .. k.query) or nil
                row = Row(k.label, 0, k.r, k.g, k.b, query)
                row.order, row.icon, row.classFile = k.order, k.icon, k.classFile
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
    return rows
end

-- The rows for a count-by and filters, with chosen looks on top:
-- rows, total, pctOf, sub.
function ST:Rows(group, filter, looks)
    local g = self:Group(group)
    if not g then return {}, 0, "members", "" end
    local members = ns.Roster:Query(filter or "")
    local rows, total, pctOf, sub
    if g.compute then
        rows, total, pctOf, sub = g.compute(members)
    else
        rows, total, pctOf, sub = CountMembers(g, members, filter), #members, "members", MembersSub(#members)
    end
    for _, row in ipairs(rows) do
        local l = looks and looks[ns.Sync.Codec.LookLabel(row.label)]
        if l then
            if l.color then row.r, row.g, row.b = D:TagColor(l.color) end
            if l.icon == false then
                row.icon, row.classFile = nil, nil -- no icon
            elseif l.icon then
                row.icon, row.classFile = l.icon, nil
            end
        end
    end
    return rows, total, pctOf, sub
end

-- Works out a stat now.
function ST:Compute(id)
    local c = self:Get(id)
    local g = c and self:Group(c.group)
    if not g then return nil end
    local s = { id = id, title = c.title, custom = c, layout = c.layout or "barspie" }
    s.rows, s.total, s.pctOf, s.sub = self:Rows(c.group, c.filter, c.looks)
    if (c.filter or "") ~= "" then s.sub = s.sub .. ("  |cff9d9d9dFilters: %s|r"):format(c.filter) end
    local notes = {}
    if g.note then notes[#notes + 1] = g.note end
    if g.multi then notes[#notes + 1] = "Percent of the members counted; someone with several counts in each." end
    s.note = #notes > 0 and table.concat(notes, " ") or nil
    return s
end
