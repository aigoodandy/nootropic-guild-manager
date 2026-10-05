--[[
    Nootropic Guild Manager - Guildmate locations
    Each copy of the addon shares its own player's map position on the GUILD
    addon channel (the game doesn't tell addons where other players are), and
    keeps the latest position of everyone else for the world map dots and the
    roster's Location column.

    Message:  3 <tab> P <tab> mapID <tab> x <tab> y     (x, y in 1/10000ths)
              mapID 0 = "stopped sharing"
    Positions are never saved or audited, and go stale after a few minutes.
]]
local _, ns = ...
local L = {}
ns.Location = L

L.CHECK_EVERY = 5      -- seconds between position checks
L.MIN_INTERVAL = 15    -- at most one update per 15 seconds while moving
L.HEARTBEAT = 60       -- resend at least once a minute while standing still
L.STALE = 180          -- forget positions older than this
L.MOVE_THRESHOLD = 0.004

L.positions = {} -- full -> { map, x, y, at }

function L:Enabled() return ns.DB:Settings().shareLocation ~= false end
function L:Showing() return ns.DB:Settings().showOnMap ~= false end

-- Our own position: mapID, x, y (nil inside instances or when unknown).
function L:Current()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function SendPosition(mapID, x, y)
    local S = ns.Sync
    S:Send(table.concat({ S.PROTO, "P", tostring(mapID), tostring(math.floor(x * 10000 + 0.5)), tostring(math.floor(y * 10000 + 0.5)) }, S.FS), "GUILD", nil, "bulk")
end

function L:Tick()
    if not IsInGuild() or not self:Enabled() then return end
    local mapID, x, y = self:Current()
    if not mapID then return end
    local now, last = GetTime(), self.last
    local moved = not last or last.map ~= mapID
        or math.abs(last.x - x) > self.MOVE_THRESHOLD or math.abs(last.y - y) > self.MOVE_THRESHOLD
    local since = last and (now - last.at) or 1e9
    if (moved and since >= self.MIN_INTERVAL) or since >= self.HEARTBEAT then
        self.last = { map = mapID, x = x, y = y, at = now }
        SendPosition(mapID, x, y)
    end
end

function L:SetSharing(on)
    ns.DB:Settings().shareLocation = on and true or false
    if not on and IsInGuild() then
        local S = ns.Sync
        S:Send(table.concat({ S.PROTO, "P", "0", "0", "0" }, S.FS), "GUILD", nil, "bulk") -- remove my dot for others
    end
    self.last = nil
    ns:Fire("SETTINGS_CHANGED")
end

function L:SetShowing(on)
    ns.DB:Settings().showOnMap = on and true or false
    ns:Fire("LOCATIONS_CHANGED")
    ns:Fire("SETTINGS_CHANGED")
end

function L:OnPosition(full, mapID, x, y)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not (full and mapID and x and y) then return end
    if not ns.Roster.byName[full] then return end -- guild members only
    if mapID == 0 then
        self.positions[full] = nil
    else
        self.positions[full] = { map = mapID, x = x / 10000, y = y / 10000, at = GetTime() }
    end
    ns:Fire("LOCATIONS_CHANGED", full)
end

-- Fresh position of a guildmate, or nil.
function L:Get(full)
    local p = self.positions[full]
    if not p then return nil end
    if GetTime() - p.at > self.STALE then
        self.positions[full] = nil
        return nil
    end
    local e = ns.Roster.byName[full]
    if e and not e.online then return nil end
    return p
end

------------------------------------------------------------------------
-- Zone names -> map ids (for the roster's Location column)
------------------------------------------------------------------------
local zoneCache
function L:MapIDForZone(zone)
    if not zone or zone == "" or not (C_Map and C_Map.GetMapInfo) then return nil end
    if not zoneCache then
        zoneCache = {}
        for id = 1, 2500 do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and info and info.name and info.name ~= "" then
                local key = info.name:lower()
                local cur = zoneCache[key]
                -- prefer zones (type 3) over other map types with the same name
                if not cur or (info.mapType == 3 and cur.type ~= 3) then
                    zoneCache[key] = { id = id, type = info.mapType }
                end
            end
        end
    end
    local hit = zoneCache[zone:lower()]
    return hit and hit.id
end

-- Best map for a guildmate: their shared position, else their roster zone.
function L:MapFor(e)
    local p = self:Get(e.full)
    if p then return p.map end
    return self:MapIDForZone(e.zone)
end

-- Opens the world map at mapID, highlighting `full`'s dot for a few seconds.
function L:OpenMap(mapID, full)
    if not mapID then return end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("The map can't be opened by an addon during combat.")
        return
    end
    self.highlight, self.highlightUntil = full, GetTime() + 6
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        if not WorldMapFrame:IsShown() then
            if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
        end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
    ns:Fire("LOCATIONS_CHANGED")
end

function L:Init()
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < L.CHECK_EVERY then return end
        elapsed = 0
        L:Tick()
    end)
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(2, function() L:Tick() end) end)
end
