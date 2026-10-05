--[[
    Nootropic Guild Manager - Main window
    Blizzard portrait frame with bottom tabs (Roster / Content Tags),
    a status line, and the member detail flyout.
]]
local _, ns = ...
local W = ns.Widgets
local UI = {}
ns.UI = UI

local FRAME_W, FRAME_H = 1000, 580
local MIN_W, MIN_H, MAX_W, MAX_H = 640, 520, 1800, 1100
local TAB_LABELS = { "Roster", "Recruitment", "Tags", "Audit" }
UI.TAB_ROSTER, UI.TAB_RECRUIT, UI.TAB_TAGS, UI.TAB_AUDIT = 1, 2, 3, 4
local OFFICER_TABS = { [3] = true, [4] = true } -- Tags and Audit

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "NootropicGMFrame", UIParent, "ButtonFrameTemplate")
    self.frame = f
    local size = ns.DB:Settings().frameSize or {}
    f:SetSize(math.max(MIN_W, math.min(MAX_W, size.w or FRAME_W)), math.max(MIN_H, math.min(MAX_H, size.h or FRAME_H)))
    f:SetToplevel(true)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    self:UpdateTitle()
    self:BuildPortrait(f)
    self:BuildOptionsButton(f)
    self:RestorePosition()

    -- Status line along the bottom edge
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("BOTTOMLEFT", 14, 8)
    self.version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.version:SetPoint("BOTTOMRIGHT", -14, 8)
    self.version:SetText("v" .. ns.version)

    ns.RosterView.LIST_WIDTH = math.floor(f:GetWidth() - ns.RosterView.LIST_INSET)
    ns.RosterView:Build(f)
    ns.RecruitView:Build(f)
    ns.TagsView:Build(f)
    ns.AuditView:Build(f)
    ns.DetailPanel:Build(f)
    self:BuildTabs(f)
    self:BuildResizeGrip(f)
    ns.TagsView:OnResize(f:GetWidth())

    f:SetScript("OnShow", ns.Safe(function()
        ns.PlaySound("IG_CHARACTER_INFO_OPEN")
        ns.CheckOfficer()
        UI:LayoutTabs()
        ns.Roster:Request()
        ns.Sync:Exchange(false)
        UI:RefreshStatus()
        ns.RosterView:Refresh()
    end, "opening the window"))
    f:SetScript("OnHide", ns.Safe(function()
        ns.PlaySound("IG_CHARACTER_INFO_CLOSE")
    end, "closing the window"))
    ns:On("OFFICER_CHANGED", function()
        UI:LayoutTabs()
        if f:IsShown() then ns.RosterView:Relayout(); ns.RosterView:Refresh() end
    end)

    ns:On("ROSTER_UPDATED", function()
        UI:UpdateTitle() -- the guild name may have just arrived
        if f:IsShown() then UI:RefreshStatus() end
    end)
    ns:On("SETTINGS_CHANGED", function() UI:UpdateTitle() end)

    self:SelectTab(1)
    return f
end

-- The portrait shows the addon icon (mug, stein or guild emblem).
function UI:BuildPortrait(f)
    self.portrait = ns.Brand:AttachPortrait(f)
end

function UI:BuildOptionsButton(f)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(20, 20)
    local close = f.CloseButton or (f.GetName and _G[f:GetName() .. "CloseButton"])
    if close then
        b:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        b:SetPoint("TOPRIGHT", -28, -4)
    end
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints()
    b.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() ns.Options:Open() end)
    W.Tooltip(b, "Options", "Icon, minimap button and Guild & Communities shortcut.")
    self.optionsButton = b
end

function UI:BuildResizeGrip(f)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
        if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        UI:SavePosition()
        UI:SaveSize()
    end)
    W.Tooltip(grip, "Drag to resize")
    self.resizeGrip = grip

    self.version:ClearAllPoints()
    self.version:SetPoint("BOTTOMRIGHT", -22, 8)

    f:SetScript("OnSizeChanged", function(self, w)
        ns.RosterView:SetListWidth((w or self:GetWidth()) - ns.RosterView.LIST_INSET)
        ns.RecruitView:OnResize()
        ns.TagsView:OnResize(w or self:GetWidth())
        ns.AuditView:OnResize()
    end)
end

function UI:SaveSize()
    local f = self.frame
    ns.DB:Settings().frameSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
end

function UI:BuildTabs(f)
    f.Tabs = {}
    local prev
    for i, label in ipairs(TAB_LABELS) do
        local tab, template = W.TryCreate("Button", "NootropicGMFrameTab" .. i, f,
            "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        tab.gap = template == "PanelTabButtonTemplate" and 3 or -15
        tab:SetScript("OnClick", function(self)
            UI:SelectTab(self:GetID())
            ns.PlaySound("IG_CHARACTER_INFO_TAB")
        end)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        if OFFICER_TABS[i] then
            tab:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(label .. " |cff9d9d9d(officers only)|r")
                GameTooltip:Show()
            end)
            tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        f.Tabs[i] = tab
    end
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #TAB_LABELS) end
    self:LayoutTabs()
end

function UI:IsTabAvailable(id)
    return not OFFICER_TABS[id] or ns.IsOfficer()
end

-- Shows only the tabs this player may use, packed left to right.
function UI:LayoutTabs()
    local f = self.frame
    if not (f and f.Tabs) then return end
    local prev
    for i, tab in ipairs(f.Tabs) do
        tab:ClearAllPoints()
        if self:IsTabAvailable(i) then
            if prev then
                tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", tab.gap or 3, 0)
            else
                tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
            end
            tab:Show()
            prev = tab
        else
            tab:Hide()
        end
    end
    if self.tab and not self:IsTabAvailable(self.tab) then self:SelectTab(UI.TAB_ROSTER) end
end

function UI:SelectTab(id)
    local f = self.frame
    if not self:IsTabAvailable(id) then id = UI.TAB_ROSTER end
    self.tab = id
    if PanelTemplates_SetTab then PanelTemplates_SetTab(f, id) end

    -- Roster and Recruitment need room above the inset for a second toolbar row.
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, (id == UI.TAB_TAGS or id == UI.TAB_AUDIT) and -64 or -86)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, 26)

    ns.RosterView.page:SetShown(id == UI.TAB_ROSTER)
    ns.RecruitView.page:SetShown(id == UI.TAB_RECRUIT)
    ns.TagsView.page:SetShown(id == UI.TAB_TAGS)
    ns.AuditView.page:SetShown(id == UI.TAB_AUDIT)
    if id ~= UI.TAB_ROSTER then ns.DetailPanel:Hide() end
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------
-- "Nootropic Guild Manager", or "<Guild Name> Guild Manager" when that option is on.
function UI:Title()
    if ns.DB:Settings().titleUseGuild and IsInGuild() then
        local guild = GetGuildInfo("player")
        if guild and guild ~= "" then return guild .. " Guild Manager" end
    end
    return "Nootropic Guild Manager"
end

function UI:UpdateTitle()
    if self.frame then W.SetTitle(self.frame, self:Title()) end
end

function UI:RefreshStatus()
    if not self.status then return end
    if not IsInGuild() then
        self.status:SetText("Not in a guild")
        return
    end
    local guild = GetGuildInfo("player") or "Guild"
    local total, online, withAddon = ns.Roster:Stats()
    self.status:SetText(("|cffffd100%s|r   %d members  -  |cff40ff40%d online|r  -  %d using Nootropic Guild Manager")
        :format(guild, total, online, withAddon))
end

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------
function UI:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    ns.DB:Settings().framePos = { point = point, relPoint = relPoint, x = x, y = y }
end

function UI:RestorePosition()
    local f, pos = self.frame, ns.DB:Settings().framePos
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -120, 40)
    end
end

function UI:ResetPosition()
    local s = ns.DB:Settings()
    s.framePos = nil
    s.frameSize = { w = FRAME_W, h = FRAME_H }
    if self.frame then
        self.frame:SetSize(FRAME_W, FRAME_H)
        self:RestorePosition()
    end
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------
function UI:Show()
    self:Create():Show()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

-- Opens the window on a tab (and refreshes it right away). If the window is
-- already showing that tab, closes it instead, so one click toggles.
function UI:OpenTab(id, toggle)
    local f = self:Create()
    if toggle and f:IsShown() and self.tab == id then
        f:Hide()
        return
    end
    f:Show()
    self:SelectTab(id)
    if id == UI.TAB_ROSTER then ns.RosterView:Refresh() end
end

function UI:Toggle()
    local f = self:Create()
    f:SetShown(not f:IsShown())
end

function UI:SetSearch(text)
    self:Create()
    self:SelectTab(1)
    ns.RosterView:SetSearch(text)
end

function UI:ShowRosterWithSearch(text)
    self:Show()
    self:SetSearch(text)
end
