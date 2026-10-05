--[[
    Nootropic Guild Manager - Self report
    The game doesn't let addons read another player's professions or talents,
    so each member's addon publishes its own (record P:<member> in Core/Sync.lua).
    Everything else about syncing lives in Core/Sync.lua; the functions at the
    bottom are kept for the buttons and commands that call them.
]]
local _, ns = ...
local C = {}
ns.Comm = C

------------------------------------------------------------------------
-- Detecting the player's own data
------------------------------------------------------------------------
local function DetectSpec()
    -- Modern specialization system
    if GetSpecialization and GetSpecializationInfo then
        local ok, index = pcall(GetSpecialization)
        if ok and index and index > 0 then
            local ok2, _, name = pcall(GetSpecializationInfo, index)
            if ok2 and name and name ~= "" then return name, nil end
        end
    end

    -- Classic talent trees: the tree with the most points is the spec
    if GetNumTalentTabs and GetTalentTabInfo then
        local ok, numTabs = pcall(GetNumTalentTabs)
        if ok and numTabs and numTabs > 0 then
            local bestName, bestPoints, dist = nil, 0, {}
            for i = 1, numTabs do
                local res = { pcall(GetTalentTabInfo, i) }
                local name, points
                if res[1] then
                    if type(res[2]) == "number" then
                        name, points = res[3], res[6] -- id, name, description, icon, pointsSpent
                    else
                        name, points = res[2], res[4] -- name, icon, pointsSpent
                    end
                end
                points = tonumber(points) or 0
                dist[#dist + 1] = points
                if type(name) == "string" and points > bestPoints then
                    bestName, bestPoints = name, points
                end
            end
            return bestName, table.concat(dist, "/")
        end
    end
end

local function DetectProfessions()
    local out = {}

    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        if ok then
            for _, index in pairs({ p1, p2, p3, p4, p5, p6 }) do
                local ok2, name, icon, rank, maxRank = pcall(GetProfessionInfo, index)
                if ok2 and name then
                    out[#out + 1] = {
                        name = name, rank = rank or 0, max = maxRank or 0,
                        icon = type(icon) == "number" and icon or nil,
                    }
                end
            end
        end
        if #out > 0 then return out end
    end

    if GetNumSkillLines and GetSkillLineInfo then
        local ok, count = pcall(GetNumSkillLines)
        if ok and count then
            local section
            for i = 1, count do
                local ok2, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
                if ok2 and name then
                    if isHeader then
                        section = name
                    elseif section == TRADE_SKILLS or section == SECONDARY_SKILLS or ns.Data:GetProfession(name) then
                        out[#out + 1] = { name = name, rank = rank or 0, max = maxRank or 0 }
                    end
                end
            end
        end
    end

    return out
end

function C:Snapshot()
    local spec, dist = DetectSpec()
    return { spec = spec, dist = dist, profs = DetectProfessions() }
end

------------------------------------------------------------------------
-- Publishing
------------------------------------------------------------------------
-- Publishes our spec/professions if they changed.
function C:Report()
    if not IsInGuild() or not ns.DB:Guild() then return end
    ns.DB:SetSelfReport(self:Snapshot())
end

-- Kept for callers: publish our data and ask peers to reconcile now.
function C:Broadcast()
    self:Report()
    ns.Sync:Exchange(true)
end

function C:RequestLog()
    ns.Sync:Exchange(true)
end

function C:MaybeRequest()
    ns.Sync:Exchange(false)
end

function C:SendLog() end -- officer log entries sync through Core/Sync.lua

function C:Init()
    local function changed()
        ns.Debounce("selfreport", 10, function() C:Report() end)
    end
    for _, event in ipairs({
        "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
        "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
    }) do
        ns:RegisterEvent(event, changed)
    end
    C_Timer.After(8, function() C:Report() end)
end
