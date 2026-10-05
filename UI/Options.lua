--[[
    Nootropic Guild Manager - Options
    A panel in the game's Options > AddOns list (also opened by /ngm options,
    or right-clicking the minimap button).
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local O = {}
ns.Options = O

local PANEL_NAME = "Nootropic Guild Manager"

local function Header(panel, text, y)
    local title, line = W.SectionHeader(panel, text)
    title:SetPoint("TOPLEFT", 16, y)
    line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    return title
end

local function Check(panel, text, tip, y, onClick)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 14, y)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    label:SetFontObject("GameFontHighlight")
    label:SetText(text)
    if tip then
        local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        hint:SetText(tip)
    end
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
-- Small dropdown-style button that picks one of D.MINIMAP_ACTIONS.
local function ActionPicker(panel, label, key, y)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 40, y - 4)
    text:SetText(label)
    local b = W.Button(panel, "", 200, 22)
    b:SetPoint("TOPLEFT", 150, y)
    b:SetScript("OnClick", function(self)
        local items = { { text = label, isTitle = true } }
        for _, a in ipairs(D.MINIMAP_ACTIONS) do
            items[#items + 1] = {
                text = a.label, radio = true,
                checked = function() return ns.DB:Settings().minimap[key] == a.key end,
                func = function()
                    ns.DB:Settings().minimap[key] = a.key
                    O:Refresh()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    b.key = key
    return b
end

function O:Build()
    local outer = CreateFrame("Frame", "NootropicGMOptionsPanel", UIParent)
    outer.name = PANEL_NAME
    outer:Hide()
    self.panel = outer

    -- Everything scrolls, so the panel fits any screen size.
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMOptionsScroll", outer, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(600, 1000)
    scroll:SetScrollChild(panel)
    outer:SetScript("OnSizeChanged", function(_, w) panel:SetWidth(math.max(400, (w or 600) - 30)) end)
    self.content = panel

    -- Title with the current icon
    self.logo = ns.Brand:Attach(panel, 40, { "TOPLEFT", panel, "TOPLEFT", 16, -16 })
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", self.logo.Slot, "TOPRIGHT", 10, -4)
    title:SetText(PANEL_NAME)
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(("Version %s  -  /ngm to open  -  /ngm help for commands"):format(ns.version))

    local y = -76

    -- Icon style
    Header(panel, "Addon Icon", y)
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 16, y - 20)
    desc:SetText("Shown at the top-left of the window, on the minimap button and on the Guild & Communities shortcut.")
    self.styleButtons = {}
    for i, style in ipairs(D.ICON_STYLES) do
        local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
        b:SetSize(120, 92)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 132, y - 40)
        b:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        b:SetBackdropColor(0, 0, 0, 0.4)
        b.Preview = ns.Brand:Attach(b, 48, { "TOP", b, "TOP", 0, -12 }, { style = style.key })
        b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.Label:SetPoint("BOTTOM", 0, 12)
        b.Label:SetText(style.label)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function()
            ns.Brand:SetStyle(style.key)
            if style.key == "emblem" and not ns.Brand:CanShowEmblem() then
                ns:Print("You'll see your guild emblem once you're in a guild with a tabard. Until then the mug is shown.")
            end
            O:Refresh()
        end)
        b.key = style.key
        self.styleButtons[i] = b
    end
    y = y - 152

    -- Minimap button
    Header(panel, "Minimap Button", y)
    self.minimapCheck = Check(panel, "Show minimap button", nil, y - 20,
        function(on) ns.Minimap:SetShown(on) end)
    self.clickPickers = {
        ActionPicker(panel, "Left-click", "left", y - 52),
        ActionPicker(panel, "Right-click", "right", y - 80),
        ActionPicker(panel, "Shift-click", "shift", y - 108),
    }
    y = y - 146

    -- Guildmate locations
    Header(panel, "Guildmate Locations", y)
    self.shareCheck = Check(panel, "Share my location with guildmates",
        "Sends your map position to guildmates using the addon (not inside dungeons). Turn off to stay hidden.", y - 20,
        function(on) ns.Location:SetSharing(on) end)
    self.mapCheck = Check(panel, "Show guildmates on the world map",
        "Class-colored dots; hover one for their roster details, click it to open their profile.", y - 66,
        function(on) ns.Location:SetShowing(on) end)
    self.customDotsCheck = Check(panel, "Custom dot colors",
        "See the dot colors guildmates picked, and pick your own. Off: every dot is its class color.", y - 112,
        function(on) ns.Location:SetCustomDots(on) end)

    -- my dot: fill and outline swatches, a preview and a reset
    local L = ns.Location
    local function myColors()
        local me = ns.PlayerFullName()
        local _, cls = UnitClass and UnitClass("player")
        local fr, fg, fb = ns.ClassColor(cls)
        local fill, outline = L:ChosenColors(me)
        if fill then fr, fg, fb = L.RGB(fill) end
        local br, bg, bb = 0, 0, 0
        if outline then br, bg, bb = L.RGB(outline) end
        return fr, fg, fb, br, bg, bb
    end
    self.dotRow = {}
    local fillLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fillLabel:SetPoint("TOPLEFT", 44, y - 162)
    fillLabel:SetText("My dot")
    self.fillSwatch = W.Swatch(panel, 18, function() local r, g, b = myColors() return r, g, b end,
        function(r, g, b) L:SetMyColor("fill", r, g, b) O:RefreshDot() end)
    self.fillSwatch:SetPoint("LEFT", fillLabel, "RIGHT", 8, 0)
    local outLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    outLabel:SetPoint("LEFT", self.fillSwatch, "RIGHT", 18, 0)
    outLabel:SetText("Outline")
    self.outlineSwatch = W.Swatch(panel, 18, function() return select(4, myColors()) end,
        function(r, g, b) L:SetMyColor("outline", r, g, b) O:RefreshDot() end)
    self.outlineSwatch:SetPoint("LEFT", outLabel, "RIGHT", 8, 0)
    -- preview, drawn like a map dot
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local prevLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    prevLabel:SetPoint("LEFT", self.outlineSwatch, "RIGHT", 18, 0)
    prevLabel:SetText("Preview")
    local pv = CreateFrame("Frame", nil, panel)
    pv:SetSize(20, 20)
    pv:SetPoint("LEFT", prevLabel, "RIGHT", 8, 0)
    pv.Border = pv:CreateTexture(nil, "ARTWORK", nil, 1)
    pv.Border:SetTexture(CIRCLE)
    pv.Border:SetAllPoints()
    pv.Dot = pv:CreateTexture(nil, "ARTWORK", nil, 2)
    pv.Dot:SetTexture(CIRCLE)
    pv.Dot:SetSize(14, 14)
    pv.Dot:SetPoint("CENTER")
    self.dotPreview = pv
    local resetDot = W.Button(panel, "Use Class Color", 130, 22)
    resetDot:SetPoint("LEFT", pv, "RIGHT", 16, 0)
    resetDot:SetScript("OnClick", function() L:ResetMyColors() O:RefreshDot() end)
    W.Tooltip(resetDot, "Use class color", "Your dot goes back to your class color with a black outline.")
    self.resetDot = resetDot
    self.dotRow = { fillLabel, self.fillSwatch, outLabel, self.outlineSwatch, prevLabel, pv, resetDot }
    y = y - 200

    -- Shortcuts and window
    Header(panel, "Window", y)
    self.communitiesCheck = Check(panel, "Show shortcut on the Guild & Communities window",
        "Adds a tab with the addon icon to the side of the Guild & Communities window.", y - 20,
        function(on) ns.Communities:SetEnabled(on) end)
    self.titleCheck = Check(panel, "Use my guild's name in the window title",
        "Shows \"<Guild Name> Guild Manager\" instead of \"Nootropic Guild Manager\" (also at the bottom of the window).", y - 66,
        function(on)
            ns.DB:Settings().titleUseGuild = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    self.addonCountCheck = Check(panel, "Show how many guildmates use the addon",
        "The \"x using ... Guild Manager\" text at the bottom of the window. Click it to list them.", y - 112,
        function(on)
            ns.DB:Settings().showAddonCount = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    local open = W.Button(panel, "Open Guild Manager", 170, 24)
    open:SetPoint("TOPLEFT", 18, y - 162)
    open:SetScript("OnClick", function() ns.UI:OpenTab(ns.UI.TAB_ROSTER) end)
    local reset = W.Button(panel, "Reset Size and Position", 190, 24)
    reset:SetPoint("LEFT", open, "RIGHT", 10, 0)
    reset:SetScript("OnClick", function()
        ns.UI:ResetPosition()
        ns:Print("Window size and position reset.")
    end)
    local cols = W.Button(panel, "Reset Roster Columns", 190, 24)
    cols:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
    cols:SetScript("OnClick", function()
        W.Confirm("Reset the roster columns to their default order, widths and visibility?", function()
            ns.RosterView:ResetColumns()
            ns:Print("Roster columns reset to defaults.")
        end)
    end)
    W.Tooltip(cols, "Reset roster columns", "Restores the default column order, widths and which columns are shown.")
    self.resetColumns = cols
    y = y - 236

    -- Text size (the addon's own text only)
    Header(panel, "Text Size", y)
    local tdesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tdesc:SetPoint("TOPLEFT", 16, y - 20)
    tdesc:SetText("Makes the text in the addon's windows bigger or smaller. The rest of your game is unchanged.")
    local smaller = W.Button(panel, "Smaller", 90, 22)
    smaller:SetPoint("TOPLEFT", 18, y - 40)
    smaller:SetScript("OnClick", function() ns.Fonts:Set(ns.Fonts:Delta() - 1) end)
    local larger = W.Button(panel, "Larger", 90, 22)
    larger:SetPoint("LEFT", smaller, "RIGHT", 6, 0)
    larger:SetScript("OnClick", function() ns.Fonts:Set(ns.Fonts:Delta() + 1) end)
    local normal = W.Button(panel, "Normal", 90, 22)
    normal:SetPoint("LEFT", larger, "RIGHT", 6, 0)
    normal:SetScript("OnClick", function() ns.Fonts:Set(0) end)
    self.fontValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.fontValue:SetPoint("LEFT", normal, "RIGHT", 14, 0)
    self.fontSmaller, self.fontLarger = smaller, larger
    local sample = panel:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    sample:SetPoint("TOPLEFT", 20, y - 72)
    sample:SetText("Preview: |cffffd100Mammoria|r  Level 20 Priest  -  Agama'gor")
    y = y - 100

    -- Recruiting
    Header(panel, "Recruiting", y)
    self.whoWhisperCheck = Check(panel, "Recruitment whisper button on /who results",
        "Adds a button to each player in the game's /who (Looking For Group) search that sends them your recruitment whisper.", y - 20,
        function(on) ns.WhoWhisper:SetEnabled(on) end)
    y = y - 70

    -- Guild-wide settings (officers change them for everyone)
    Header(panel, "Guild Settings  |cff9d9d9d(officers, for the whole guild)|r", y)
    self.reviewsCheck = Check(panel, "Guildmates can review the guild",
        "When off, guildmates don't see the Review Guild tab. Officers still see every review.", y - 20,
        function(on)
            local ok, err = ns.DB:SetReviewsEnabled(on)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
            O:Refresh()
        end)
    y = y - 70

    -- Audit history (officers)
    Header(panel, "Audit History  |cff9d9d9d(officers)|r", y)
    local adesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    adesc:SetPoint("TOPLEFT", 16, y - 20)
    adesc:SetText("How long to keep the record of who changed what. Older entries are deleted.")
    self.auditRadios = {}
    for i, days in ipairs({ 30, 60, 90 }) do
        local rb = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", 18 + (i - 1) * 110, y - 40)
        local label = rb.text or rb.Text
        if type(label) ~= "table" then label = nil end
        if not label then
            label = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        end
        label:SetFontObject("GameFontHighlight")
        label:SetText(days .. " days")
        rb.days = days
        rb:SetScript("OnClick", function()
            ns.DB:Settings().auditDays = days
            local removed = ns.Sync:PruneAudit() or 0
            if removed > 0 then ns:Print(("Removed %d audit entries older than %d days."):format(removed, days)) end
            O:Refresh()
        end)
        self.auditRadios[i] = rb
    end
    y = y - 74

    -- Sync status
    self.syncStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.syncStatus:SetPoint("TOPLEFT", 16, y)
    self.syncStatus:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    self.syncStatus:SetJustifyH("LEFT")
    panel:SetHeight(-y + 40)

    outer:SetScript("OnShow", function() O:Refresh() end)
    ns:On("SETTINGS_CHANGED", function() if outer:IsShown() then O:Refresh() end end)
    ns:On("BRAND_CHANGED", function() if outer:IsShown() then O:Refresh() end end)
    ns:On("GUILD_SETTINGS_CHANGED", function() if outer:IsShown() then O:Refresh() end end)
    ns:On("FONTS_CHANGED", function() if outer:IsShown() then O:Refresh() end end)
end

function O:Refresh()
    local s = ns.DB:Settings()
    for _, b in ipairs(self.styleButtons) do
        if b.key == (s.iconStyle or "mug") then
            b:SetBackdropBorderColor(1, 0.82, 0, 1)
            b:SetBackdropColor(0.25, 0.2, 0, 0.6)
        else
            b:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            b:SetBackdropColor(0, 0, 0, 0.4)
        end
        b.Preview:Apply()
    end
    self.minimapCheck:SetChecked(not s.minimap.hide)
    for _, b in ipairs(self.clickPickers) do b:SetText(D:MinimapActionLabel(s.minimap[b.key])) end
    self.shareCheck:SetChecked(s.shareLocation ~= false)
    self.mapCheck:SetChecked(s.showOnMap ~= false)
    self.customDotsCheck:SetChecked(s.customDots == true)
    self:RefreshDot()
    self.communitiesCheck:SetChecked(s.communitiesButton ~= false)
    self.titleCheck:SetChecked(s.titleUseGuild and true or false)
    self.addonCountCheck:SetChecked(s.showAddonCount ~= false)
    self.whoWhisperCheck:SetChecked(s.whoWhisperButton ~= false)
    local delta = ns.Fonts:Delta()
    self.fontValue:SetText("Text size: |cffffd100" .. ns.Fonts:Label() .. "|r")
    self.fontSmaller:SetEnabled(delta > ns.Fonts.MIN)
    self.fontLarger:SetEnabled(delta < ns.Fonts.MAX)
    local officer = ns.IsOfficer()
    self.reviewsCheck:SetChecked(ns.DB:ReviewsEnabled())
    self.reviewsCheck:SetEnabled(officer and ns.DB:Guild() ~= nil)
    self.reviewsCheck:SetAlpha(officer and 1 or 0.5)
    for _, rb in ipairs(self.auditRadios) do rb:SetChecked((s.auditDays or 30) == rb.days) end
    local st = ns.Sync.stats
    self.syncStatus:SetText(("Sync this session: %d sent, %d received, %d applied, %d waiting to send.  |cffffffff/ngm sync|r runs one now.")
        :format(st.sent, st.received, st.applied, ns.Sync:QueueSize()))
end

-- Your dot's swatches and preview; only usable while custom colors are on.
function O:RefreshDot()
    if not self.dotRow then return end
    local on = ns.Location:CustomDots()
    for _, w in ipairs(self.dotRow) do w:SetAlpha(on and 1 or 0.35) end
    self.fillSwatch:SetEnabled(on)
    self.outlineSwatch:SetEnabled(on)
    self.resetDot:SetEnabled(on)
    self.fillSwatch:Update()
    self.outlineSwatch:Update()
    local _, cls = UnitClass and UnitClass("player")
    local fr, fg, fb = ns.ClassColor(cls)
    local fill, outline = ns.Location:ChosenColors(ns.PlayerFullName())
    local br, bg, bb = 0, 0, 0
    if on and fill then fr, fg, fb = ns.Location.RGB(fill) end
    if on and outline then br, bg, bb = ns.Location.RGB(outline) end
    self.dotPreview.Dot:SetVertexColor(fr, fg, fb)
    self.dotPreview.Border:SetVertexColor(br, bg, bb, 0.9)
end

------------------------------------------------------------------------
-- Registration with the game's options window
------------------------------------------------------------------------
function O:Init()
    self:Build()
    local panel = self.panel
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function O:Open()
    if not self.panel then return end
    if Settings and Settings.OpenToCategory and self.category then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call only opens the frame on some clients.
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
