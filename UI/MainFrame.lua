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
local TAB_LABELS = { "Roster", "Recruitment", "Insights", "Tags", "Audit", "Reviews" }
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
    self:BuildCompactButton(f)
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
        if f:IsShown() then
            UI:RefreshStatus()
            UI:LayoutTabs() -- your rank may have changed
        end
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

-- Red Compact arrow beside the close button (as on the spellbook), on the
-- Roster tab (compact roster) and the Recruitment tab (small recruiting bar).
function UI:BuildCompactButton(f)
    local close = f.CloseButton or (f.GetName and _G[f:GetName() .. "CloseButton"])
    local size = close and math.floor(close:GetWidth() + 0.5) or 24
    if size < 16 then size = 24 end
    local mini = W.SizeButton(f, "condense", size, function()
        if UI.tab == UI.TAB_RECRUIT then
            ns.RecruitMini:Compact()
        else
            ns.CompactRoster:Compact()
        end
    end)
    if close then
        mini:SetPoint("RIGHT", close, "LEFT", 0, 0)
    else
        mini:SetPoint("TOPRIGHT", -28, -2)
    end
    mini:MatchLevel(close)
    mini.Button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Compact")
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

------------------------------------------------------------------------
-- Tabs: icon tabs down the right side of the window, built exactly like
-- the character panel's (CharacterFrameModeTab1..: a 55x55 frame, the
-- common-sidetab art at 55x60, a 50x50 icon nudged 4 left, the
-- common-sidetab-selected art when chosen, common-sidetab-hover on hover,
-- each tab 2 below the last). Hover one for its title.
-- Clients without that art fall back to the spellbook's tab art.
------------------------------------------------------------------------
local TAB_SIZE, TAB_GAP = 55, 2
UI.TAB_OUTSIDE = 55 -- how far the tabs reach past the window's right edge

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- An icon file if this client has it, else the fallback.
local function IconIfPresent(path, fallback)
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and id then return path end
        if ok then return fallback end
    end
    return path
end

-- The usual icon of each tab (officers can pick another in Options).
UI.DEFAULT_TAB_ICONS = {
    -- a group of people, as on the Guild & Communities window's roster tab
    IconIfPresent("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude"), -- Roster
    "Interface\\Icons\\Ability_Warrior_BattleShout",  -- Recruitment
    "Interface\\Icons\\INV_Scroll_03",                -- Insights
    "Interface\\Icons\\INV_Misc_Note_01",             -- Tags
    "Interface\\Icons\\INV_Misc_Spyglass_02",         -- Audit
    "Interface\\Icons\\INV_Scroll_05",                -- Reviews
}

-- Flips a texture left to right (keeps an atlas's own coordinates).
local function Mirror(tex)
    local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
    tex:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly)
end

-- Where the tabs are: "right" (default), "left" (icon tabs down that side)
-- or "bottom" (the classic text tabs under the window). Options >
-- Appearance; each player's own choice.
function UI:TabSide()
    local side = ns.DB:Settings().tabSide
    return (side == "left" or side == "bottom") and side or "right"
end

function UI:TabsOnLeft()
    return self:TabSide() == "left"
end

-- The classic text tabs along the bottom edge.
local function CreateBottomTab(f, i)
    local tab, template = W.TryCreate("Button", "NootropicGMFrameBottomTab" .. i, f,
        "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab.gap = template == "PanelTabButtonTemplate" and 3 or -15
    tab:SetScript("OnClick", function(self)
        UI:SelectTab(self:GetID())
        ns.PlaySound("IG_CHARACTER_INFO_TAB")
    end)
    if OFFICER_TABS[i] then
        tab:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(UI:TabTitle(self:GetID()) .. " |cff9d9d9d(officers only)|r")
            GameTooltip:Show()
        end)
        tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function tab:SetSelected(on)
        if on then
            if PanelTemplates_SelectTab then PanelTemplates_SelectTab(self) end
        elseif PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(self)
        end
    end
    tab:Hide()
    return tab
end

local function CreateSideTab(f, i)
    local tab = CreateFrame("CheckButton", "NootropicGMFrameTab" .. i, f)
    if HasAtlas("common-sidetab") then
        -- the character panel's tabs
        tab:SetSize(TAB_SIZE, TAB_SIZE)
        tab.Bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.Bg:SetAtlas("common-sidetab")
        tab.Bg:SetSize(55, 60)
        tab.Bg:SetPoint("CENTER")
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetSize(50, 50)
        tab.Icon:SetPoint("CENTER", -4, 0)
        tab.iconCoords = { 0.031, 0.969, 0.031, 0.969 }
        -- trims the icon to the tab's beveled shape (the same mask Blizzard uses)
        if HasAtlas("common-sidetab-mask") and tab.CreateMaskTexture then
            local mask = tab:CreateMaskTexture()
            mask:SetAtlas("common-sidetab-mask", false)
            mask:SetSize(55, 60)
            mask:SetPoint("CENTER")
            tab.Icon:AddMaskTexture(mask)
            tab.Mask = mask
        end
        tab.Selected = tab:CreateTexture(nil, "OVERLAY")
        tab.Selected:SetAtlas("common-sidetab-selected")
        tab.Selected:SetSize(55, 60)
        tab.Selected:SetPoint("CENTER")
        tab.Selected:Hide()
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("common-sidetab-hover")
        hl:SetSize(55, 60)
        hl:SetPoint("CENTER")
        tab.Hl = hl
        tab.atlases = { Bg = "common-sidetab", Selected = "common-sidetab-selected", Hl = "common-sidetab-hover", Mask = "common-sidetab-mask" }
        tab.iconX = 4
        tab.gap = TAB_GAP
    else
        -- older clients: the spellbook's skill line tab
        tab:SetSize(32, 32)
        tab.Bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.Bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        tab.Bg:SetSize(64, 64)
        tab.Bg:SetPoint("TOPLEFT", -3, 11)
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetAllPoints()
        tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        tab.Selected = tab:CreateTexture(nil, "OVERLAY")
        tab.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        tab.Selected:SetBlendMode("ADD")
        tab.Selected:SetAllPoints()
        tab.Selected:Hide()
        tab.gap = 17
    end
    tab:SetID(i)
    -- shows or hides the selected art (instead of a checked texture)
    function tab:SetSelected(on) self.Selected:SetShown(on and true or false) end
    -- Puts the tab's art the right way round for its side: the art opens
    -- toward the window, so on the left it's mirrored.
    function tab:SetSide(left)
        if self.side == left then return end
        self.side = left
        if self.atlases then
            -- the frame, selected border and hover glow are mirrored; the icon
            -- never is
            for key, atlas in pairs(self.atlases) do
                local tex = self[key]
                if tex and key ~= "Mask" then
                    tex:SetAtlas(atlas)
                    if left then pcall(Mirror, tex) end
                end
            end
            -- The shaped trim can't be mirrored (the game then hides the whole
            -- icon), but it can be turned: the tab is the same shape top and
            -- bottom, so half a turn gives the left-side shape. Where turning
            -- isn't possible, the icon goes untrimmed and a little smaller.
            if self.Mask then
                self.Mask:SetAtlas(self.atlases.Mask, false)
                local turned = false
                if left and self.Mask.SetRotation then
                    turned = pcall(self.Mask.SetRotation, self.Mask, math.pi)
                elseif self.Mask.SetRotation then
                    pcall(self.Mask.SetRotation, self.Mask, 0)
                end
                if left and not turned then
                    self.Icon:RemoveMaskTexture(self.Mask)
                    self.Icon:SetSize(44, 44)
                else
                    self.Icon:RemoveMaskTexture(self.Mask)
                    self.Icon:AddMaskTexture(self.Mask)
                    self.Icon:SetSize(50, 50)
                end
            end
            self.Icon:ClearAllPoints()
            self.Icon:SetPoint("CENTER", left and self.iconX or -self.iconX, 0)
        else
            self.Bg:SetTexCoord(left and 1 or 0, left and 0 or 1, 0, 1)
            self.Bg:ClearAllPoints()
            if left then self.Bg:SetPoint("TOPRIGHT", 3, 11) else self.Bg:SetPoint("TOPLEFT", -3, 11) end
        end
    end
    tab:SetScript("OnClick", function(self)
        UI:SelectTab(self:GetID())
        ns.PlaySound("IG_CHARACTER_INFO_TAB")
    end)
    tab:SetScript("OnEnter", function(self)
        local id = self:GetID()
        GameTooltip:SetOwner(self, self.side and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        GameTooltip:AddLine(UI:TabTitle(id) .. (OFFICER_TABS[id] and " |cff9d9d9d(officers only)|r" or ""))
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

function UI:BuildTabs(f)
    f.Tabs = {}
    f.BottomTabs = {}
    for i in ipairs(TAB_LABELS) do
        f.Tabs[i] = CreateSideTab(f, i)
        f.BottomTabs[i] = CreateBottomTab(f, i)
    end
    self:LayoutTabs()
end

-- The icon officers gave the tab, or its usual one.
function UI:TabIcon(id)
    local _, _, icon = ns.DB:TabSetting(ns.DB.TAB_KEYS[id])
    return icon or self.DEFAULT_TAB_ICONS[id]
end

function UI:IsTabAvailable(id)
    -- officers choose which ranks see each tab (Options > Officers)
    if id ~= UI.TAB_ROSTER and not ns.DB:TabAllowedForMe(ns.DB.TAB_KEYS[id]) then return false end
    if id == UI.TAB_REVIEWS then
        -- officers can turn reviews off; then only officers see the tab
        return ns.IsOfficer() or ns.DB:ReviewsEnabled()
    end
    return not OFFICER_TABS[id] or ns.IsOfficer()
end

-- The tab's usual name (Reviews is "Review Guild" for non-officers, who
-- write reviews rather than read them).
function UI:DefaultTabTitle(id)
    if id == UI.TAB_REVIEWS and not ns.IsOfficer() then return "Review Guild" end
    return TAB_LABELS[id]
end

-- The title officers gave the tab, or its usual name.
function UI:TabTitle(id)
    local _, title = ns.DB:TabSetting(ns.DB.TAB_KEYS[id])
    return title or self:DefaultTabTitle(id)
end

-- The classic text tabs under the window, left to right.
function UI:LayoutBottomTabs()
    local f = self.frame
    local prev
    for i, tab in ipairs(f.BottomTabs) do
        local label = self:TabTitle(i)
        if tab:GetText() ~= label then
            tab:SetText(label)
            if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        end
        tab:ClearAllPoints()
        if self:IsTabAvailable(i) then
            if prev then
                tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", tab.gap or 3, 0)
            else
                tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
            end
            tab:Show()
            tab:SetSelected(i == self.tab)
            prev = tab
        else
            tab:Hide()
        end
    end
end

-- Shows only the tabs this player may use: down the chosen side, or along the bottom.
function UI:LayoutTabs()
    local f = self.frame
    if not (f and f.Tabs) then return end
    local side = self:TabSide()
    local left = side == "left"
    -- keep the tabs on screen when the window is dragged to that edge
    if f.SetClampRectInsets then
        if side == "bottom" then
            f:SetClampRectInsets(0, 0, 0, -32)
        elseif left then
            f:SetClampRectInsets(-UI.TAB_OUTSIDE, 0, 0, 0)
        else
            f:SetClampRectInsets(0, UI.TAB_OUTSIDE, 0, 0)
        end
    end
    if side == "bottom" then
        for _, tab in ipairs(f.Tabs) do tab:Hide() end
        self:LayoutBottomTabs()
        if self.tab and not self:IsTabAvailable(self.tab) then self:SelectTab(UI.TAB_ROSTER) end
        self:UpdateTitle()
        return
    end
    for _, tab in ipairs(f.BottomTabs or {}) do tab:Hide() end
    local prev
    for i, tab in ipairs(f.Tabs) do
        tab:SetSide(left)
        W.SetIcon(tab.Icon, self:TabIcon(i))
        if tab.iconCoords then tab.Icon:SetTexCoord(unpack(tab.iconCoords)) end
        tab:ClearAllPoints()
        if self:IsTabAvailable(i) then
            if prev then
                if left then
                    tab:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -tab.gap)
                else
                    tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -tab.gap)
                end
            elseif left then
                -- below the round portrait in the top-left corner
                tab:SetPoint("TOPRIGHT", f, "TOPLEFT", 2, -72)
            else
                tab:SetPoint("TOPLEFT", f, "TOPRIGHT", -2, -48)
            end
            tab:SetSelected(i == self.tab)
            tab:Show()
            prev = tab
        else
            tab:Hide()
        end
    end
    if self.tab and not self:IsTabAvailable(self.tab) then self:SelectTab(UI.TAB_ROSTER) end
    self:UpdateTitle()
end

function UI:SelectTab(id)
    local f = self.frame
    if not self:IsTabAvailable(id) then id = UI.TAB_ROSTER end
    self.tab = id
    for i, tab in ipairs(f.Tabs or {}) do tab:SetSelected(i == id) end
    for i, tab in ipairs(f.BottomTabs or {}) do
        if tab:IsShown() then tab:SetSelected(i == id) end
    end
    self:UpdateTitle()

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

-- The window title, with the open tab's name ("Nootropic Guild Manager - Insights").
function UI:UpdateTitle()
    if not self.frame then return end
    local title = self:Title()
    if self.tab and self.frame.Tabs then title = title .. "  |cffffffff-  " .. self:TabTitle(self.tab) .. "|r" end
    W.SetTitle(self.frame, title)
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
    ns.RosterView:ShowAddonUsers() -- Filter > Only guildmates using the addon
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
