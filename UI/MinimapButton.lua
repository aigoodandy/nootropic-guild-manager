--[[
    Nootropic Guild Manager - Minimap button
    Standard round minimap button; drag to move around the minimap edge.
]]
local _, ns = ...
local M = {}
ns.Minimap = M

local function UpdatePosition(button)
    local angle = math.rad(ns.DB:Settings().minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate(button)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.DB:Settings().minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition(button)
end

function M:Init()
    if not Minimap then return end
    local b = CreateFrame("Button", "NootropicGMMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    -- Same icon as the window portrait (mug, stein or guild emblem).
    self.icon = ns.Brand:Attach(b, 20, { "TOPLEFT", b, "TOPLEFT", 7, -5 })

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        local s = ns.DB:Settings().minimap
        local action
        if IsShiftKeyDown and IsShiftKeyDown() then
            action = s.shift
        elseif button == "RightButton" then
            action = s.right
        else
            action = s.left
        end
        M:Run(action)
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Nootropic Guild Manager")
        local s = ns.DB:Settings().minimap
        GameTooltip:AddDoubleLine("Left-click", ns.Data:MinimapActionLabel(s.left), 1, 1, 1, 0.8, 0.8, 0.8)
        GameTooltip:AddDoubleLine("Right-click", ns.Data:MinimapActionLabel(s.right), 1, 1, 1, 0.8, 0.8, 0.8)
        GameTooltip:AddDoubleLine("Shift-click", ns.Data:MinimapActionLabel(s.shift), 1, 1, 1, 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = b
    UpdatePosition(b)
    b:SetShown(not ns.DB:Settings().minimap.hide)
end

-- Runs a click action from Options > Minimap Button.
function M:Run(action)
    local UI = ns.UI
    if action == "roster" then UI:OpenTab(UI.TAB_ROSTER, true)
    elseif action == "recruit" then UI:OpenTab(UI.TAB_RECRUIT, true)
    elseif action == "tags" then UI:OpenTab(ns.IsOfficer() and UI.TAB_TAGS or UI.TAB_ROSTER, true)
    elseif action == "audit" then UI:OpenTab(ns.IsOfficer() and UI.TAB_AUDIT or UI.TAB_ROSTER, true)
    elseif action == "options" then ns.Options:Open()
    elseif action == "toggle" then UI:Toggle()
    end
end

function M:SetShown(shown)
    ns.DB:Settings().minimap.hide = not shown
    if self.button then self.button:SetShown(shown) end
    ns:Fire("SETTINGS_CHANGED")
end

function M:IsShown()
    return not ns.DB:Settings().minimap.hide
end

function M:ToggleShown()
    self:SetShown(not self:IsShown())
    ns:Print(self:IsShown() and "Minimap button shown." or "Minimap button hidden. /ngm minimap or the options bring it back.")
end
