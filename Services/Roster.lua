--[[
    Nootropic Guild Manager - Roster service
    Reads the guild roster, merges it with saved data, and provides
    searching and sorting. Fires ROSTER_UPDATED when the list changes.

    Search syntax (case-insensitive, all words must match):
      mage fire              free words match name, class, spec, tags, professions
      tag:raiding            field filter (name, tag, prof, spec, class, rank, zone, note)
      tag:"world pvp"        quotes keep phrases together
      main:markpri           a main and all of their alts
      is:alt  is:main        only alts / only mains
      is:addon               only members running Nootropic Guild Manager
      rating:4  rating<3     numeric filters (rating:N means N stars or more)
      level:60  level>=50
      -raiding               a leading minus excludes matches
]]
local _, ns = ...
local D = ns.Data
local R = {}
ns.Roster = R

R.members = {}  -- array of entries
R.byName = {}   -- fullName -> entry
R.altIndex = {} -- main fullName -> sorted list of alt fullNames

local EMPTY = {}

function R:Init()
    local function queue() ns.Debounce("roster", 0.25, function() R:Rebuild() end) end
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", queue)
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", queue)

    ns:On("MEMBER_CHANGED", function(full)
        local e = R.byName[full]
        if e then R:Decorate(e) end
        ns:Fire("ROSTER_UPDATED")
    end)
    local function redecorate()
        R:BuildAltIndex()
        for _, e in ipairs(R.members) do R:Decorate(e) end
        ns:Fire("ROSTER_UPDATED")
    end
    ns:On("TAGS_CHANGED", redecorate)
    ns:On("LINKS_CHANGED", redecorate)
    ns:On("OFFICER_CHANGED", redecorate) -- officer-only fields appear or disappear

    self:Request()
end

function R:Request()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

------------------------------------------------------------------------
-- Building entries
------------------------------------------------------------------------
function R:BuildAltIndex()
    wipe(self.altIndex)
    local g = ns.DB:Guild()
    if not g then return end
    for name, m in pairs(g.members) do
        if m.main then
            local list = self.altIndex[m.main]
            if not list then
                list = {}
                self.altIndex[m.main] = list
            end
            list[#list + 1] = name
        end
    end
    for _, list in pairs(self.altIndex) do table.sort(list) end
end

function R:Rebuild()
    wipe(self.members)
    wipe(self.byName)
    self:BuildAltIndex()

    if IsInGuild() then
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local name, rankName, rankIndex, level, classDisplay, zone, publicNote,
                  officerNote, online, status, classFile = GetGuildRosterInfo(i)
            if name then
                local full = ns.NormalizeName(name)
                local e = {
                    full = full,
                    short = ns.ShortName(full),
                    first = nil, second = nil, -- set below
                    rank = rankName or "",
                    rankIndex = rankIndex or 99,
                    level = level or 0,
                    className = classDisplay or "",
                    classFile = classFile or "",
                    zone = zone or "",
                    publicNote = publicNote or "",
                    officerNote = officerNote or "",
                    online = online and true or false,
                    status = status or 0,
                    lastOnline = 0,
                }
                if not e.online and GetGuildRosterLastOnline then
                    local y, mo, d, h = GetGuildRosterLastOnline(i)
                    e.lastOnline = (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24) + (h or 0)
                end
                self:Decorate(e)
                self.members[#self.members + 1] = e
                self.byName[full] = e
            end
        end
        self:FindSelf(total)
    end

    ns:Fire("ROSTER_UPDATED")
end

-- Finds your own row (by character GUID, else by name) and makes sure the
-- addon uses that exact spelling for you.
function R:FindSelf(total)
    local myGuid = UnitGUID and UnitGUID("player")
    local myName = (UnitName("player") or ""):lower()
    local found, byName
    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        if name then
            local guid = select(17, GetGuildRosterInfo(i))
            if myGuid and guid and guid == myGuid then
                found = ns.NormalizeName(name)
                break
            end
            if not byName and ns.ShortName(name):lower() == myName then byName = ns.NormalizeName(name) end
        end
    end
    found = found or byName
    self.selfRow = found
    if found and found ~= ns.PlayerFullName() then
        ns.selfName = found
        ns:Fire("SELF_NAME_CHANGED", found)
    end
    local e = found and self.byName[found]
    if e then self:Decorate(e) end
end

local function SortProfs(a, b)
    local pa, pb = D:IsPrimary(a.name), D:IsPrimary(b.name)
    if pa ~= pb then return pa end
    if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
    return a.name < b.name
end

-- Merges saved data into a roster entry and builds its search index.
function R:Decorate(e)
    e.first, e.second = ns.SplitName(e.short)
    local m = ns.DB:GetMember(e.full)
    local auto = m and m.auto

    -- Specialization: a manual override wins over addon-reported data.
    if m and m.spec then
        e.spec, e.specSource = m.spec, "manual"
    elseif auto and auto.spec and auto.spec ~= "" then
        e.spec, e.specSource = auto.spec, "addon"
    else
        e.spec, e.specSource = nil, nil
    end
    e.dist = auto and auto.dist ~= "" and auto.dist or nil
    e.version = m and m.version
    e.isSelf = e.full == ns.PlayerFullName()
    if e.isSelf then e.version = ns.version end -- you're running this copy right now
    e.hasAddon = auto ~= nil or e.version ~= nil
    e.syncedAt = auto and auto.ts

    -- Professions: addon-reported data first, manual entries fill the gaps.
    local profs, seen = {}, {}
    if auto and auto.profs then
        for _, p in ipairs(auto.profs) do
            local key = p.name:lower()
            if not seen[key] then
                seen[key] = true
                profs[#profs + 1] = { name = p.name, rank = p.rank or 0, max = p.max or 0, icon = p.icon, source = "addon" }
            end
        end
    end
    if m and m.profs then
        for _, p in ipairs(m.profs) do
            local key = p.name:lower()
            if not seen[key] then
                seen[key] = true
                profs[#profs + 1] = { name = p.name, rank = p.rank or 0, max = 0, source = "manual" }
            end
        end
    end
    table.sort(profs, SortProfs)
    e.profs = profs

    -- Tags, kept in the user's tag order.
    local tagList, tagNames = {}, {}
    local set = (m and m.tags) or EMPTY
    for _, tag in ipairs(ns.DB:GetTags()) do
        if set[tag.id] then
            tagList[#tagList + 1] = tag
            tagNames[#tagNames + 1] = tag.name
        end
    end
    e.tagList, e.tagSet = tagList, set
    e.rating = (ns.IsOfficer() and m and m.rating) or 0 -- ratings are officer-only
    e.note = m and m.note

    -- Main / alt
    e.main = m and m.main
    e.isAlt = e.main ~= nil
    e.mainShort = e.main and ns.ShortName(e.main)
    e.alts = self.altIndex[e.full] or EMPTY

    -- Officer log (only searchable for officers)
    local logText = ""
    if m and m.log and ns.IsOfficer() then
        local parts = {}
        for _, entry in pairs(m.log) do
            if not entry.del then parts[#parts + 1] = entry.text end
        end
        logText = table.concat(parts, "\n")
    end

    -- Search index (lowercase).
    local profNames = {}
    for i, p in ipairs(profs) do profNames[i] = p.name end
    local s = e.search or {}
    e.search = s
    s.name  = e.short:lower()
    s.class = (e.className .. " " .. e.classFile):lower()
    s.spec  = (e.spec or ""):lower()
    s.tags  = table.concat(tagNames, "\n"):lower()
    s.profs = table.concat(profNames, "\n"):lower()
    s.rank  = e.rank:lower()
    s.zone  = e.zone:lower()
    s.note  = ((e.note or "") .. "\n" .. e.publicNote .. "\n" .. e.officerNote .. "\n" .. logText):lower()
    s.main  = (e.mainShort or e.short):lower()
    s.is    = (e.isAlt and "alt" or "main") .. (e.hasAddon and "\naddon" or "")
end

------------------------------------------------------------------------
-- Searching
------------------------------------------------------------------------
local FIELDS = {
    name = "name", n = "name",
    tag = "tags", tags = "tags", t = "tags", content = "tags",
    prof = "profs", profs = "profs", profession = "profs", p = "profs",
    spec = "spec", s = "spec",
    class = "class", c = "class",
    rank = "rank",
    zone = "zone", z = "zone",
    note = "note", notes = "note",
    rating = "rating", r = "rating", skill = "rating",
    level = "level", lvl = "level", l = "level",
    main = "main", m = "main",
    is = "is", type = "is",
}
local NUMERIC = { rating = true, level = true }
local DEFAULT_FIELDS = { "name", "class", "spec", "tags", "profs" }

local function Tokenize(text)
    local out, i, n = {}, 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local buf, inQuote = {}, false
            while i <= n do
                local ch = text:sub(i, i)
                if ch == '"' then
                    inQuote = not inQuote
                elseif ch:match("%s") and not inQuote then
                    break
                else
                    buf[#buf + 1] = ch
                end
                i = i + 1
            end
            if #buf > 0 then out[#out + 1] = table.concat(buf) end
        end
    end
    return out
end

function R:ParseQuery(text)
    local tokens = {}
    for _, raw in ipairs(Tokenize((text or ""):lower())) do
        local t = {}
        if #raw > 1 and raw:sub(1, 1) == "-" then
            t.neg = true
            raw = raw:sub(2)
        end
        local key, op, rest = raw:match("^(%a+)([:=<>]+)(.*)$")
        local field = key and FIELDS[key]
        if field then
            t.field = field
            if NUMERIC[field] then
                op = op:gsub(":", "")
                if rest:sub(-1) == "+" then op = ">=" end
                if op ~= ">" and op ~= "<" and op ~= ">=" and op ~= "<=" and op ~= "=" then
                    op = (field == "rating") and ">=" or "="
                end
                t.op, t.num = op, tonumber(rest:match("%d+"))
            else
                t.value = rest
            end
        else
            t.value = raw
        end
        tokens[#tokens + 1] = t
    end
    return tokens
end

local function Compare(v, op, n)
    if op == ">=" then return v >= n
    elseif op == "<=" then return v <= n
    elseif op == ">" then return v > n
    elseif op == "<" then return v < n
    end
    return v == n
end

local function MatchToken(e, t)
    local hit
    if t.field and NUMERIC[t.field] then
        if not t.num then return true end -- incomplete filter, ignore
        if t.field == "rating" and not ns.IsOfficer() then return true end
        local v = (t.field == "rating") and e.rating or e.level
        hit = Compare(v, t.op, t.num)
    elseif t.field then
        hit = t.value == "" or e.search[t.field]:find(t.value, 1, true) ~= nil
    else
        hit = false
        for _, f in ipairs(DEFAULT_FIELDS) do
            if e.search[f]:find(t.value, 1, true) then
                hit = true
                break
            end
        end
    end
    if t.neg then return not hit end
    return hit
end

-- opts: { onlineOnly = bool, tagIds = { [id] = true } }
function R:Query(text, opts)
    opts = opts or EMPTY
    local tokens = self:ParseQuery(text)
    local out = {}
    for _, e in ipairs(self.members) do
        local ok = not (opts.onlineOnly and not e.online)
        if ok and opts.tagIds then
            for id in pairs(opts.tagIds) do
                if not e.tagSet[id] then ok = false break end
            end
        end
        if ok then
            for _, t in ipairs(tokens) do
                if not MatchToken(e, t) then ok = false break end
            end
        end
        if ok then out[#out + 1] = e end
    end
    return out
end

------------------------------------------------------------------------
-- Sorting
------------------------------------------------------------------------
-- Each comparator returns a<b when the keys differ, or nil when they tie.
local SORTERS = {
    name = function(a, b)
        if a.short ~= b.short then return a.short < b.short end
    end,
    second = function(a, b)
        if a.second ~= b.second then
            if a.second == "" then return false end
            if b.second == "" then return true end
            return a.second < b.second
        end
        if a.first ~= b.first then return a.first < b.first end
    end,
    level = function(a, b)
        if a.level ~= b.level then return a.level < b.level end
    end,
    class = function(a, b)
        if a.className ~= b.className then return a.className < b.className end
    end,
    spec = function(a, b)
        local sa, sb = a.spec or "~", b.spec or "~"
        if sa ~= sb then return sa < sb end
        if a.className ~= b.className then return a.className < b.className end
    end,
    -- groups each main with their alts
    zone = function(a, b)
        local za, zb = a.zone ~= "" and a.zone or "~", b.zone ~= "" and b.zone or "~"
        if za ~= zb then return za < zb end
    end,
    main = function(a, b)
        local fa, fb = (a.mainShort or a.short), (b.mainShort or b.short)
        if fa ~= fb then return fa < fb end
        if a.isAlt ~= b.isAlt then return b.isAlt end
    end,
    profs = function(a, b)
        local pa = a.profs[1] and a.profs[1].name or "~"
        local pb = b.profs[1] and b.profs[1].name or "~"
        if pa ~= pb then return pa < pb end
    end,
    tags = function(a, b)
        if #a.tagList ~= #b.tagList then return #a.tagList < #b.tagList end
    end,
    rating = function(a, b)
        if a.rating ~= b.rating then return a.rating < b.rating end
    end,
    rank = function(a, b)
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
    end,
    version = function(a, b)
        local c = ns.CompareVersions(a.version or (a.hasAddon and "0" or ""), b.version or (b.hasAddon and "0" or ""))
        if c ~= 0 then return c < 0 end
    end,
}
R.DEFAULT_DESC = { level = true, rating = true, tags = true }

function R:Sort(list, key, asc)
    local cmp = SORTERS[key]
    table.sort(list, function(a, b)
        if cmp then
            local r = cmp(a, b)
            if r ~= nil then
                if asc then return r end
                return not r
            end
        end
        if a.online ~= b.online then return a.online end
        if a.short ~= b.short then return a.short < b.short end
        return a.full < b.full
    end)
    return list
end

------------------------------------------------------------------------
-- Stats
------------------------------------------------------------------------
function R:Stats()
    local total, online, withAddon = #self.members, 0, 0
    for _, e in ipairs(self.members) do
        if e.online then online = online + 1 end
        if e.hasAddon then withAddon = withAddon + 1 end
    end
    return total, online, withAddon
end

function R:TagCount(id)
    local n = 0
    for _, e in ipairs(self.members) do
        if e.tagSet[id] then n = n + 1 end
    end
    return n
end

------------------------------------------------------------------------
-- Addon versions
------------------------------------------------------------------------
-- The newest version of the addon anyone in the guild runs (including you).
function R:NewestVersion()
    local newest = ns.version
    local g = ns.DB:Guild()
    for _, m in pairs(g and g.members or {}) do
        if type(m) == "table" and m.version and ns.CompareVersions(m.version, newest) > 0 then newest = m.version end
    end
    return newest
end

-- Is this member's copy older than the newest one in the guild?
function R:IsOutdated(e)
    if not e.hasAddon then return false end
    if not e.version then return true end -- 1.10 or older never said
    return ns.CompareVersions(e.version, self:NewestVersion()) < 0
end

-- /ngm diag: how the addon sees you, and what version record it has for you.
function R:Diagnose()
    local me = ns.PlayerFullName()
    local fromUnit = ns.NormalizeName(UnitName("player"))
    local rec = ns.Sync:Get("AV:" .. me)
    local m = ns.DB:GetMember(me)
    local e = self.byName[me]
    ns:Print(("Version: running %s. You are \"%s\"%s; roster row %s; shared version record %s; saved version %s."):format(
        ns.version, me, fromUnit ~= me and (" (UnitName gives \"" .. fromUnit .. "\")") or "",
        e and "found" or "|cffff5555not found|r", rec and ("\"" .. rec.v .. "\"") or "|cffff5555missing|r",
        m and m.version or "none"))
end

-- Tells you (once per session) when a guildmate has a newer version.
function R:CheckVersion()
    local newest = self:NewestVersion()
    if self.toldNewer ~= newest and ns.CompareVersions(newest, ns.version) > 0 then
        self.toldNewer = newest
        ns:Print(("A newer version (%s) is in use in your guild. You have %s."):format(newest, ns.version))
    end
end

