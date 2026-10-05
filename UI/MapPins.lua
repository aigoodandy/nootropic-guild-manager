--[[
    Nootropic Guild Manager - Guildmates on the world map
    Class-colored dots for guildmates who share their location (see
    Services/Location.lua). Hovering a dot shows the roster tooltip; clicking
    it opens that guildmate's profile. Dots are drawn on whatever map is
    displayed (zone or continent), converting positions between maps.

    Our dots are plain frames on the map canvas; nothing of Blizzard's map is
    modified, so the map stays usable in combat.
]]
local _, ns = ...
local MP = {}
ns.MapPins = MP

local DOT = 12
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
MP.pins = {}

-- Position on `toMap` for a point on `fromMap` (nil when off that map).
function MP.Translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y))
    if not ok or not continent or not world then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, toMap)
    if not ok2 or not pos then return nil end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

local function CanvasScale()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok and v and v > 0 then return v end
    end
    return 1
end

local function CreatePin(canvas)
    local p = CreateFrame("Button", nil, canvas)
    p:SetSize(DOT, DOT)
    p.Border = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.Border:SetTexture(CIRCLE)
    p.Border:SetVertexColor(0, 0, 0, 0.9)
    p.Border:SetPoint("CENTER")
    p.Dot = p:CreateTexture(nil, "ARTWORK", nil, 2)
    p.Dot:SetTexture(CIRCLE)
    p.Dot:SetPoint("CENTER")
    p:SetScript("OnEnter", function(self)
        local e = self.full and ns.Roster.byName[self.full]
        if e then ns.RosterView:ShowRowTooltip(self, e, "Click to open their profile.") end
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self)
        if self.full then
            ns.UI:OpenTab(ns.UI.TAB_ROSTER)
            ns.RosterView:Select(self.full)
        end
    end)
    return p
end

function MP:Refresh()
    if not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return end
    local shown = 0
    local visible = WorldMapFrame:IsShown() and ns.Location:Showing()
    local mapID = visible and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if mapID then
        local w, h = canvas:GetWidth(), canvas:GetHeight()
        local size = DOT / CanvasScale()
        local me = ns.PlayerFullName()
        local now = GetTime()
        for full in pairs(ns.Location.positions) do
            local p = ns.Location:Get(full)
            local e = ns.Roster.byName[full]
            if p and e and full ~= me then
                local x, y = MP.Translate(p.map, p.x, p.y, mapID)
                if x then
                    shown = shown + 1
                    local pin = self.pins[shown]
                    if not pin then
                        pin = CreatePin(canvas)
                        self.pins[shown] = pin
                    end
                    pin.full = full
                    local hl = ns.Location.highlight == full and now < (ns.Location.highlightUntil or 0)
                    local s = hl and size * 1.6 or size
                    pin:SetSize(s, s)
                    pin.Border:SetSize(s, s)
                    pin.Dot:SetSize(s * 0.72, s * 0.72)
                    pin.Dot:SetVertexColor(ns.ClassColor(e.classFile))
                    pin:SetFrameLevel(canvas:GetFrameLevel() + (hl and 2100 or 2000))
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
                    pin:Show()
                end
            end
        end
    end
    for i = shown + 1, #self.pins do self.pins[i]:Hide() end
    self.count = shown
end

function MP:Attach()
    if self.attached or not WorldMapFrame then return end
    self.attached = true
    WorldMapFrame:HookScript("OnShow", function() MP:Refresh() end)
    WorldMapFrame:HookScript("OnHide", function() MP:Refresh() end)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() MP:Refresh() end)
    end
    -- keep dots current (movement, zoom) while the map is open
    local driver = CreateFrame("Frame")
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.5 then return end
        elapsed = 0
        if WorldMapFrame:IsShown() then MP:Refresh() end
    end)
    self:Refresh()
end

function MP:Init()
    ns:On("LOCATIONS_CHANGED", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then MP:Refresh() end
    end)
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_WorldMap" then MP:Attach() end
    end)
    self:Attach()
end
