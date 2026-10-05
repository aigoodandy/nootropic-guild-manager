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
local TAB_LABELS = { "Roster", "Recruitment", "Polls", "Tags", "Audit", "Reviews" }
UI.TAB_ROSTER, UI.TAB_RECRUIT, UI.TAB_POLLS, UI.TAB_TAGS, UI.TAB_AUDIT, UI.TAB_REVIEWS = 1, 2, 3, 4, 5, 6
local OFFICER_TABS = { [4] = true, [5] = true } -- Tags and Audit

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
    self:BuildMinimizeButton(f)
    self:RestorePosition()

    -- Status line along the bottom edge
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("BOTTOMLEFT", 14, 8)
    self:BuildAddonCount(f)
    self.version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.version:SetPoint("BOTTOMRIGHT", -14, 8)
    self.version:SetText("v" .. ns.version)

    ns.RosterView.LIST_WIDTH = math.floor(f:GetWidth() - ns.RosterView.LIST_INSET)
    ns.RosterView:Build(f)
    ns.RecruitView:Build(f)
    ns.PollsView:Build(f)
    ns.TagsView:Build(f)
    ns.AuditView:Build(f)
    ns.ReviewsView:Build(f)
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
        -- whispers still going out: keep the controls on screen in the small bar
        if ns.Recruit:IsSending() and not ns.RecruitMini:IsShown() then ns.RecruitMini:Show() end
    end, "closing the window"))
    ns:On("OFFICER_CHANGED", function()
        UI:LayoutTabs()
        if f:IsShown() then ns.RosterView:Relayout(); ns.RosterView:Refresh() end
    end)

    ns:On("ROSTER_UPDATED", function()
        UI:UpdateTitle() -- the guild name may have just arrived
        if f:IsShown() then UI:RefreshStatus() end
    end)
    ns:On("SETTINGS_CHANGED", function()
        UI:UpdateTitle()
        UI:RefreshStatus()
    end)
    ns:On("GUILD_SETTINGS_CHANGED", function() UI:LayoutTabs() end)

    self:SelectTab(1)
    return f
end

-- The portrait shows the addon icon (mug, stein or guild emblem).
function UI:BuildPortrait(f)
    self.portrait = ns.Brand:AttachPortrait(f)
end

-- Red minimize arrow beside the close button, on the Roster tab (compact
-- roster) and the Recruitment tab (small recruiting bar).
function UI:BuildMinimizeButton(f)
    local close = f.CloseButton or (f.GetName and _G[f:GetName() .. "CloseButton"])
    local size = close and math.floor(close:GetWidth() + 0.5) or 24
    if size < 16 then size = 24 end
    local mini = W.SizeButton(f, "condense", size, function()
        if UI.tab == UI.TAB_RECRUIT then
            ns.RecruitMini:Minimize()
        else
            ns.CompactRoster:Minimize()
        end
    end)
    if close then
        mini:SetPoint("RIGHT", close, "LEFT", 0, 0)
    else
        mini:SetPoint("TOPRIGHT", -28, -2)
    end
    mini:SetFrameLevel(f:GetFrameLevel() + 10)
    mini.Button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Minimize")
        if UI.tab == UI.TAB_RECRUIT then
            GameTooltip:AddLine("A small recruiting bar you can move anywhere: search, tick new players and send whispers while you play.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("A small guild roster you can move anywhere: names and locations.", 1, 1, 1, true)
        end
        GameTooltip:AddLine("Its expand arrow brings you back here.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    mini.Button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    mini:Hide()
    self.miniButton = mini
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
    if id == UI.TAB_REVIEWS then
        -- officers can turn reviews off; then only officers see the tab
        return ns.IsOfficer() or ns.DB:ReviewsEnabled()
    end
    return not OFFICER_TABS[id] or ns.IsOfficer()
end

-- Shows only the tabs this player may use, packed left to right.
function UI:LayoutTabs()
    local f = self.frame
    if not (f and f.Tabs) then return end
    -- officers read reviews; everyone else writes one
    local reviews = f.Tabs[UI.TAB_REVIEWS]
    local label = ns.IsOfficer() and "Reviews" or "Review Guild"
    if reviews:GetText() ~= label then
        reviews:SetText(label)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, reviews, 0) end
    end
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
    f.Inset:SetPoint("TOPLEFT", 4, (id == UI.TAB_ROSTER or id == UI.TAB_RECRUIT) and -86 or -64)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, 26)

    ns.RosterView.page:SetShown(id == UI.TAB_ROSTER)
    ns.RecruitView.page:SetShown(id == UI.TAB_RECRUIT)
    if self.miniButton then self.miniButton:SetShown(id == UI.TAB_RECRUIT or id == UI.TAB_ROSTER) end
    ns.PollsView.page:SetShown(id == UI.TAB_POLLS)
    ns.TagsView.page:SetShown(id == UI.TAB_TAGS)
    ns.AuditView.page:SetShown(id == UI.TAB_AUDIT)
    ns.ReviewsView.page:SetShown(id == UI.TAB_REVIEWS)
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

-- "x using <title>" after the status line. Click: roster of addon users with versions.
function UI:BuildAddonCount(f)
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(16)
    b:SetPoint("LEFT", self.status, "RIGHT", 0, 0)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.Text:SetPoint("LEFT", 0, 0)
    b.Underline = b:CreateTexture(nil, "OVERLAY")
    b.Underline:SetHeight(1)
    b.Underline:SetColorTexture(1, 0.82, 0, 0.8)
    b.Underline:Hide()
    b:SetScript("OnEnter", function(self)
        self.Underline:ClearAllPoints()
        self.Underline:SetPoint("TOPLEFT", self.Text, "BOTTOMLEFT", self.dashWidth or 0, -1)
        self.Underline:SetPoint("TOPRIGHT", self.Text, "BOTTOMRIGHT", 0, -1)
        self.Underline:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Who uses the addon?")
        GameTooltip:AddLine("Click to list guildmates running it, with the version each one has.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.Underline:Hide()
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() UI:ShowAddonUsers() end)
    self.addonCount = b
end

-- Roster tab, Version column on, only members running the addon.
function UI:ShowAddonUsers()
    local hidden = ns.DB:Settings().hiddenColumns
    if hidden.version ~= false then hidden.version = false end
    self:Show()
    self:SelectTab(UI.TAB_ROSTER)
    ns.RosterView:Relayout()
    ns.RosterView:SetSearch("is:addon")
    ns.RosterView:Refresh()
    ns.PlaySound("IG_CHARACTER_INFO_TAB")
end

function UI:RefreshStatus()
    if not self.status then return end
    local count = self.addonCount
    if not IsInGuild() then
        self.status:SetText("Not in a guild")
        count:Hide()
        return
    end
    local guild = GetGuildInfo("player") or "Guild"
    local total, online, withAddon = ns.Roster:Stats()
    self.status:SetText(("|cffffd100%s|r   %d members  -  |cff40ff40%d online|r"):format(guild, total, online))
    if ns.DB:Settings().showAddonCount == false then
        count:Hide()
        return
    end
    -- the dash isn't part of the underline
    local dash = "  -  "
    count.Text:SetText(dash)
    count.dashWidth = count.Text:GetStringWidth()
    count.Text:SetText(dash .. ("%d using %s"):format(withAddon, self:Title()))
    count:SetWidth(math.ceil(count.Text:GetStringWidth()) + 2)
    count:Show()
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
