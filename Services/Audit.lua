--[[
    Nootropic Guild Manager - Audit formatting
    Turns audit entries from Core/Sync.lua into readable text and categories
    for the Audit tab and the profile History section (officers only).
]]
local _, ns = ...
local AU = {}
ns.Audit = AU

AU.CATEGORIES = {
    { key = "GM", label = "Joined / left" },
    { key = "GK", label = "Promotions / demotions" },
    { key = "LV", label = "Level ups" },
    { key = "GN", label = "Guild notes" },
    { key = "NC", label = "Name changes" },
    { key = "M",  label = "Main / Alt" },
    { key = "MS", label = "Spec" },
    { key = "RL", label = "Role" },
    { key = "MP", label = "Professions" },
    { key = "P",  label = "Reported by their addon" },
    { key = "L",  label = "Officer log" },
    { key = "CN", label = "Contact" },
    { key = "GS", label = "Guild settings" },
    { key = "DN", label = "Do Not Whisper" },
}

local GREEN, RED, GRAY = "|cff20ff20", "|cffff2020", "|cff9d9d9d"

-- Who made a change. Changes noticed in the guild roster (level-ups, note
-- edits, renames) have no known author.
function AU.Who(author)
    if not author or author == "" then return "Guild roster" end
    return ns.ShortName(author)
end

local function Quote(text)
    if text == "" then return GRAY .. "empty|r" end
    return "\"" .. text .. "\""
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
    if t == "GM" then
        if new == "join" or new == "rejoin" then
            local how = new == "rejoin" and "Rejoined the guild" or "Joined the guild"
            return GREEN .. how .. "|r" .. ((e.ref and e.ref ~= "") and (" (invited by " .. ShortChar(e.ref) .. ")") or "")
        end
        if new == "quit" then return RED .. "Left the guild|r" end
        if new == "remove" then return RED .. "Removed from the guild|r" end
        return "Membership changed"
    elseif t == "GK" then
        local verb = e.ref == "demote" and "Demoted to " or "Promoted to "
        return verb .. new .. (old ~= "" and (GRAY .. " (was " .. old .. ")|r") or "")
    elseif t == "LV" then
        return ("Level %s to %s"):format(old, new)
    elseif t == "GN" then
        local which = e.ref == "officer" and "Officer note" or "Public note"
        if new == "" then return which .. " cleared" .. GRAY .. " (was " .. Quote(old) .. ")|r" end
        return which .. ": " .. Quote(new) .. (old ~= "" and (GRAY .. " (was " .. Quote(old) .. ")|r") or "")
    elseif t == "NC" then
        return ("Renamed from %s to %s"):format(ShortChar(old), ShortChar(new))
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
    elseif t == "GS" then
        local perm = (e.ref or ""):match("^perm_(.+)$")
        local def = perm and ns.DB:PermDef(perm)
        if def then
            local function Who(v)
                if v == "" then return ns.DB:PermDefaultText(perm) .. " (default)" end
                if v == "-" then return "Guild Master only" end
                local names = {}
                for _, r in ipairs(ns.DB:GuildRanks()) do
                    for n in v:gmatch("%d+") do if tonumber(n) == r.index then names[#names + 1] = r.name end end
                end
                return #names > 0 and table.concat(names, ", ") or v
            end
            return ("Permission \"%s\" set to %s"):format(def.label, Who(new))
        end
        return "Guild setting changed: " .. (e.ref or "?")
    elseif t == "CN" then
        local function D2(v) return (v or ""):match("^([^;]*)") or "" end
        local od, nd = D2(old), D2(new)
        local who = e.author and e.member and e.author ~= e.member and (" by " .. ShortChar(e.author)) or ""
        if nd == "" then return RED .. "Discord cleared|r" .. who end
        return ("Discord changed%s: %s"):format(who, nd)
    elseif t == "RL" then
        local function Names(v)
            local out = {}
            for key in v:gmatch("[^,]+") do
                local r = ns.Data:Role(key)
                out[#out + 1] = r and r.label or key
            end
            return #out > 0 and table.concat(out, ", ") or "none"
        end
        return "Role set to " .. Names(new) .. (old ~= "" and (GRAY .. " (was " .. Names(old) .. ")|r") or "")
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
