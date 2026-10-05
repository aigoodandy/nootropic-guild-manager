--[[
    Nootropic Guild Manager - Audit formatting
    Turns audit entries from Core/Sync.lua into readable text and categories
    for the Audit tab and the profile History section (officers only).
]]
local _, ns = ...
local D = ns.Data
local AU = {}
ns.Audit = AU

AU.CATEGORIES = {
    { key = "MT", label = "Tags" },
    { key = "RT", label = "Rating" },
    { key = "M",  label = "Main / Alt" },
    { key = "MS", label = "Spec" },
    { key = "MP", label = "Professions" },
    { key = "P",  label = "Reported by their addon" },
    { key = "L",  label = "Officer log" },
    { key = "T",  label = "Tag list" },
    { key = "TI", label = "Tag icons" },
    { key = "PL", label = "Polls" },
    { key = "SD", label = "Guild stats" },
    { key = "SO", label = "Officer stats" },
    { key = "AB", label = "About me" },
    { key = "PN", label = "Pronouns" },
    { key = "KT", label = "Kudos list" },
    { key = "KD", label = "Kudos descriptions" },
    { key = "GS", label = "Guild settings" },
    { key = "DN", label = "Do Not Whisper" },
}

local GREEN, RED, GRAY = "|cff40ff40", "|cffff6060", "|cff9d9d9d"

local function TagName(id)
    local rec = ns.Sync:Get("T:" .. id)
    local def = rec and ns.Sync.Codec.ParseTagDef(rec.v)
    return def and def.name or id
end

local function SetDiff(old, new, nameOf)
    local a, b = ns.Sync.Codec.ParseSet(old), ns.Sync.Codec.ParseSet(new)
    local parts = {}
    for id in pairs(b) do if not a[id] then parts[#parts + 1] = GREEN .. "+" .. nameOf(id) .. "|r" end end
    for id in pairs(a) do if not b[id] then parts[#parts + 1] = RED .. "-" .. nameOf(id) .. "|r" end end
    table.sort(parts)
    return table.concat(parts, "  ")
end

local function NameList(v)
    local names = {}
    for _, p in ipairs(ns.Sync.Codec.ParseProfs(v)) do names[p.name] = p.rank end
    return names
end

local function ShortChar(full)
    return full and full ~= "" and ns.ShortName(full) or "?"
end

-- Readable description of one entry.
function AU:Describe(e)
    local t, old, new = e.typ, e.old or "", e.new or ""
    if t == "MT" then
        local diff = SetDiff(old, new, TagName)
        return "Tags: " .. (diff ~= "" and diff or GRAY .. "unchanged|r")
    elseif t == "RT" then
        local o, n = tonumber(old) or 0, tonumber(new) or 0
        return ("Rating changed from %s to %s"):format(D:StarText(o), D:StarText(n))
    elseif t == "M" then
        if new ~= "" and old == "" then return "Marked as an alt of " .. ShortChar(new) end
        if new == "" then return "Unlinked from main " .. ShortChar(old) .. " (now a main)" end
        return ("Main changed from %s to %s"):format(ShortChar(old), ShortChar(new))
    elseif t == "MS" then
        if new == "" then return "Spec override cleared" .. (old ~= "" and (GRAY .. " (was " .. old .. ")|r") or "") end
        return "Spec set to " .. new .. (old ~= "" and (GRAY .. " (was " .. old .. ")|r") or "")
    elseif t == "MP" then
        local a, b = NameList(old), NameList(new)
        local parts = {}
        for name, rank in pairs(b) do
            if a[name] == nil then
                parts[#parts + 1] = GREEN .. "+" .. name .. "|r"
            elseif a[name] ~= rank then
                parts[#parts + 1] = ("%s %d to %d"):format(name, a[name], rank)
            end
        end
        for name in pairs(a) do if b[name] == nil then parts[#parts + 1] = RED .. "-" .. name .. "|r" end end
        table.sort(parts)
        return "Professions: " .. table.concat(parts, "  ")
    elseif t == "P" then
        local oldSpec, oldProfs = old:match("^([^;]*);(.*)$")
        local newSpec, newProfs = new:match("^([^;]*);(.*)$")
        oldSpec, oldProfs = oldSpec or "", oldProfs or ""
        newSpec, newProfs = newSpec or "", newProfs or ""
        local parts = {}
        if oldSpec ~= newSpec then
            parts[#parts + 1] = oldSpec ~= "" and ("spec %s to %s"):format(oldSpec, newSpec ~= "" and newSpec or "none")
                or ("spec " .. (newSpec ~= "" and newSpec or "none"))
        end
        local diff = SetDiff(oldProfs, newProfs, function(x) return x end)
        if diff ~= "" then parts[#parts + 1] = diff end
        if #parts == 0 then return "Their addon reported new data" end
        return "Their addon reported " .. table.concat(parts, ", ")
    elseif t == "L" then
        local o, n = ns.Sync.Codec.ParseLog(old), ns.Sync.Codec.ParseLog(new)
        if n and not o then return "Officer log: \"" .. n.text .. "\"" end
        if o and not n then return RED .. "Officer log entry deleted:|r \"" .. o.text .. "\"" end
        return "Officer log entry edited"
    elseif t == "DN" then
        local who = e.ref and ns.ShortName(e.ref) or "?"
        if new == "" then return "Removed " .. who .. " from the Do Not Whisper list" end
        local reply = new:match("^%d+;(.*)$")
        return "Added " .. who .. " to the Do Not Whisper list" .. ((reply and reply ~= "") and (GRAY .. " (said \"" .. reply .. "\")|r") or "")
    elseif t == "T" then
        local o, n = ns.Sync.Codec.ParseTagDef(old), ns.Sync.Codec.ParseTagDef(new)
        if n and not o then return "Tag created: " .. n.name end
        if n and n.deleted and not (o and o.deleted) then return RED .. "Tag deleted:|r " .. n.name end
        if o and n and o.name ~= n.name then return ("Tag renamed from %s to %s"):format(o.name, n.name) end
        if o and n and o.color ~= n.color then return "Tag color changed: " .. n.name end
        if o and n and o.order ~= n.order then return "Tag moved: " .. n.name end
        return "Tag changed: " .. (n and n.name or "?")
    elseif t == "TI" then
        local icon = D:ParseIcon(new)
        return "Tag icon changed: " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. TagName(e.ref or "?")
    elseif t == "GS" then
        if e.ref == "reviews" then
            return new == "0" and (RED .. "Guild reviews turned off|r for guildmates") or (GREEN .. "Guild reviews turned on|r for guildmates")
        elseif e.ref == "pronouns" then
            return new == "1" and (GREEN .. "Pronouns on profiles turned on|r") or (RED .. "Pronouns on profiles turned off|r")
        end
        return "Guild setting changed: " .. (e.ref or "?")
    elseif t == "AB" then
        if new == "" then
            local who = e.author and e.member and e.author ~= e.member and (" by " .. ShortChar(e.author)) or ""
            return RED .. "About me cleared|r" .. who
        end
        return "About me changed"
    elseif t == "PN" then
        if new == "" then
            local who = e.author and e.member and e.author ~= e.member and (" by " .. ShortChar(e.author)) or ""
            return RED .. "Pronouns cleared|r" .. who
        end
        return "Pronouns set to " .. new
    elseif t == "KT" then
        local o, n = ns.Sync.Codec.ParseKudosType(old), ns.Sync.Codec.ParseKudosType(new)
        if n and not o then return "Kudos added: " .. n.name end
        if o and n and n.retired ~= o.retired then
            return (n.retired and (RED .. "Kudos retired:|r ") or (GREEN .. "Kudos brought back:|r ")) .. n.name
        end
        if o and n and o.name ~= n.name then return ("Kudos renamed from %s to %s"):format(o.name, n.name) end
        if o and n and o.order ~= n.order then return "Kudos moved: " .. n.name end
        return "Kudos changed: " .. (n and n.name or "?")
    elseif t == "PI" then
        local rec = ns.Sync:Get("PL:" .. (e.ref or ""))
        local poll = rec and ns.Sync.Codec.ParsePoll(rec.v)
        return "Poll icon or color changed" .. (poll and (": \"" .. poll.question .. "\"") or "")
    elseif t == "SD" or t == "SO" then
        local o, n = ns.Sync.Codec.ParseCustomStat(old), ns.Sync.Codec.ParseCustomStat(new)
        local who = t == "SD" and "Guild stat" or "Officer stat"
        local title = n and n.title or (o and o.title) or "?"
        if n and not o then return who .. " created: " .. title end
        if n and n.deleted and not (o and o.deleted) then return RED .. who .. " deleted:|r " .. title end
        return who .. " changed: " .. title
    elseif t == "KD" then
        local k = e.ref and ns.Profile:KudosType(e.ref)
        local name = k and k.name or (e.ref or "?")
        if new == "" then return "Kudos description cleared: " .. name end
        return "Kudos description changed: " .. name .. GRAY .. " (\"" .. new .. "\")|r"
    elseif t == "PL" then
        local o, n = ns.Sync.Codec.ParsePoll(old), ns.Sync.Codec.ParsePoll(new)
        local q = n and n.question or (o and o.question) or "?"
        if n and not o then return "Poll created: \"" .. q .. "\"" end
        if n and n.deleted and not (o and o.deleted) then return RED .. "Poll deleted:|r \"" .. q .. "\"" end
        if o and n and n.closeAt < o.closeAt then return "Poll closed early: \"" .. q .. "\"" end
        return "Poll changed: \"" .. q .. "\""
    end
    return t .. " changed"
end

function AU:CategoryLabel(typ)
    for _, c in ipairs(self.CATEGORIES) do
        if c.key == typ then return c.label end
    end
    return typ
end

-- Entries filtered by { member = full, category = typ, text = "search" }.
function AU:Entries(filter)
    filter = filter or {}
    local out = {}
    if not ns.IsOfficer() then return out end
    local text = filter.text and ns.Trim(filter.text):lower() or ""
    for _, e in ipairs(ns.Sync:AuditEntries()) do
        if (not filter.member or e.member == filter.member)
            and (not filter.category or e.typ == filter.category) then
            if text == "" then
                out[#out + 1] = e
            else
                e.desc = e.desc or self:Describe(e)
                local hay = ((e.member and ns.ShortName(e.member) or "") .. " " .. ns.ShortName(e.author or "") .. " "
                    .. e.desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " " .. self:CategoryLabel(e.typ)):lower()
                if hay:find(text, 1, true) then out[#out + 1] = e end
            end
        end
    end
    return out
end

-- Groups entries made together (same author and batch) into one item each,
-- newest first: { key, t, author, entries = {...}, members = { full = true }, memberCount }
function AU:Group(entries)
    local groups, byKey = {}, {}
    for _, e in ipairs(entries) do
        local key = e.batch and ((e.author or "") .. "#" .. e.batch) or ("id:" .. e.id)
        local g = byKey[key]
        if not g then
            g = { key = key, t = e.t, author = e.author, entries = {}, members = {}, memberCount = 0 }
            byKey[key] = g
            groups[#groups + 1] = g
        end
        g.entries[#g.entries + 1] = e
        if e.t > g.t then g.t = e.t end
        if e.member and not g.members[e.member] then
            g.members[e.member] = true
            g.memberCount = g.memberCount + 1
            g.member = g.member or e.member
        end
    end
    table.sort(groups, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.key > b.key
    end)
    return groups
end

-- Each entry as its own group (when grouping is turned off).
function AU:Ungrouped(entries)
    local out = {}
    for _, e in ipairs(entries) do
        out[#out + 1] = { key = "id:" .. e.id, t = e.t, author = e.author, entries = { e },
            members = e.member and { [e.member] = true } or {}, memberCount = e.member and 1 or 0, member = e.member }
    end
    return out
end

-- One-line summary of a group, plus the full list for tooltips.
function AU:Summary(g)
    local first = g.entries[1]
    first.desc = first.desc or self:Describe(first)
    if #g.entries == 1 then return first.desc end
    return ("%s  |cff9d9d9d(+%d more)|r"):format(first.desc, #g.entries - 1)
end
