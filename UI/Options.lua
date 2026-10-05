--[[
    Nootropic Guild Manager - Options
    Pages in the game's Options > AddOns list (also opened by /ngm options,
    or right-clicking the minimap button):

      Nootropic Guild Manager   appearance, minimap button, reset, about
        Recruiting              /who whisper button, auto-invite, Do Not Whisper
        Map                     guildmate locations and dot colors
        Officers                guild reviews on/off, audit history

    O:Open(key) opens one: nil (main), "recruiting", "map" or "officers".
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local O = {}
ns.Options = O

local PANEL_NAME = "Nootropic Guild Manager"
O.pages = {}   -- key -> outer frame
O.subcats = {} -- key -> settings category

------------------------------------------------------------------------
-- Layout: each page stacks rows top to bottom with a cursor
------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function Layout:Header(text)
    local title, line = W.SectionHeader(self.panel, text)
    title:SetPoint("TOPLEFT", 16, self.y)
    line:SetPoint("RIGHT", self.panel, "RIGHT", -16, 0)
    self.y = self.y - 26
    return title
end

-- A checkbox with an optional one-line hint under it.
function Layout:Check(text, hint, onClick)
    local cb = CreateFrame("CheckButton", nil, self.panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 14, self.y)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    label:SetFontObject("GameFontHighlight")
    label:SetText(text)
    if hint then
        local h = self.panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        h:SetText(hint)
        cb.Hint = h
    end
    cb:SetScript("OnClick", function(b) onClick(b:GetChecked() and true or false) end)
    self.y = self.y - (hint and 42 or 30)
    return cb
end

-- A line of text (wraps to the page width).
function Layout:Text(text, font, gap)
    local fs = self.panel:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 18, self.y)
    fs:SetPoint("RIGHT", self.panel, "RIGHT", -18, 0)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(3)
    fs:SetText(text)
    self.y = self.y - math.max(14, math.ceil(fs:GetStringHeight() or 14)) - (gap or 8)
    return fs
end

-- Reserves `height` and returns the top of that row.
function Layout:Row(height)
    local y = self.y
    self.y = self.y - height
    return y
end

function Layout:Space(n) self.y = self.y - (n or 10) end

function Layout:Finish() self.panel:SetHeight(-self.y + 30) end

-- A scrolling page with a title. Returns the outer frame and a layout.
local function NewPage(key, name, subtitle)
    local outer = CreateFrame("Frame", "NootropicGMOptions" .. key, UIParent)
    outer.name = name
    outer:Hide()
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMOptionsScroll" .. key, outer, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(600, 800)
    scroll:SetScrollChild(panel)
    outer:SetScript("OnSizeChanged", function(_, w) panel:SetWidth(math.max(400, (w or 600) - 30)) end)
    outer:SetScript("OnShow", function() O:Refresh() end)
    O.pages[key] = outer

    local logo = ns.Brand:Attach(panel, 36, { "TOPLEFT", panel, "TOPLEFT", 16, -14 })
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo.Slot, "TOPRIGHT", 10, -2)
    title:SetText(key == "main" and PANEL_NAME or (PANEL_NAME .. "  |cffffffff-  " .. name .. "|r"))
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(subtitle)
    O.logos = O.logos or {}
    O.logos[#O.logos + 1] = logo
    return outer, setmetatable({ panel = panel, y = -66 }, Layout)
end

-- Small dropdown-style button that picks one of D.MINIMAP_ACTIONS.
local function ActionPicker(L, label, key)
    local y = L:Row(28)
    local text = L.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 42, y - 4)
    text:SetText(label)
    local b = W.Button(L.panel, "", 200, 22)
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

-- Five small word boxes (keywords, Do Not Whisper words), three per row.
local function WordBoxes(L, maxLetters, onChange)
    local boxes = {}
    local top = L:Row(54)
    for i = 1, D.MAX_KEYWORDS do
        local eb = CreateFrame("EditBox", nil, L.panel, "InputBoxTemplate")
        eb:SetSize(120, 20)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetMaxLetters(maxLetters)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        eb:SetPoint("TOPLEFT", 26 + col * 132, top - row * 26)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:HookScript("OnTextChanged", function(self, user) if user then onChange(i, ns.Trim(self:GetText())) end end)
        boxes[i] = eb
    end
    return boxes
end

local function RecruitChanged() ns:Fire("RECRUITS_CHANGED") end

------------------------------------------------------------------------
-- Main page: appearance, minimap button, reset, about
------------------------------------------------------------------------
function O:BuildMain()
    local outer, L = NewPage("main", PANEL_NAME,
        ("Version %s  -  /ngm to open  -  more settings on the Recruiting, Map and Officers pages below this one"):format(ns.version))
    self.panel = outer

    L:Header("Appearance")
    local y = L:Row(34)
    local iconLabel = L.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    iconLabel:SetPoint("TOPLEFT", 18, y - 8)
    iconLabel:SetText("Addon icon")
    self.iconPreview = ns.Brand:Attach(L.panel, 28, { "TOPLEFT", L.panel, "TOPLEFT", 110, y - 2 })
    local iconBtn = W.Button(L.panel, "", 160, 22)
    iconBtn:SetPoint("TOPLEFT", 148, y - 4)
    iconBtn:SetScript("OnClick", function(btn)
        local items = { { text = "Addon icon", isTitle = true } }
        for _, style in ipairs(D.ICON_STYLES) do
            items[#items + 1] = {
                text = style.label, radio = true,
                checked = function() return (ns.DB:Settings().iconStyle or "mug") == style.key end,
                func = function()
                    ns.Brand:SetStyle(style.key)
                    if style.key == "emblem" and not ns.Brand:CanShowEmblem() then
                        ns:Print("You'll see your guild emblem once you're in a guild with a tabard. Until then the mug is shown.")
                    end
                    O:Refresh()
                end,
            }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(iconBtn, "Addon icon", "Shown on the window, the minimap button and the Guild & Communities shortcut.")
    self.iconButton = iconBtn

    self.titleCheck = L:Check("Use my guild's name in the window title",
        "\"<Guild> Guild Manager\" instead of \"Nootropic Guild Manager\".", function(on)
            ns.DB:Settings().titleUseGuild = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    self.addonCountCheck = L:Check("Show how many guildmates use the addon",
        "The \"x using ... Guild Manager\" text at the bottom of the window.", function(on)
            ns.DB:Settings().showAddonCount = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    self.communitiesCheck = L:Check("Shortcut on the Guild & Communities window",
        "A side tab with the addon icon.", function(on) ns.Communities:SetEnabled(on) end)
    L:Space(4)

    L:Header("Minimap Button")
    self.minimapCheck = L:Check("Show minimap button", nil, function(on) ns.Minimap:SetShown(on) end)
    self.clickPickers = {
        ActionPicker(L, "Left-click", "left"),
        ActionPicker(L, "Right-click", "right"),
        ActionPicker(L, "Shift-click", "shift"),
    }
    L:Space(8)

    L:Header("Reset")
    y = L:Row(32)
    local resetWin = W.Button(L.panel, "Window Size and Position", 190, 24)
    resetWin:SetPoint("TOPLEFT", 18, y)
    resetWin:SetScript("OnClick", function()
        ns.UI:ResetPosition()
        ns:Print("Window size and position reset.")
    end)
    local resetCols = W.Button(L.panel, "List Columns", 140, 24)
    resetCols:SetPoint("LEFT", resetWin, "RIGHT", 8, 0)
    resetCols:SetScript("OnClick", function()
        W.Confirm("Reset the columns of the roster, the compact roster and the recruitment list to their default order, widths and visibility?", function()
            ns.RosterView:ResetColumns()
            ns.CompactRoster.cols:Reset()
            ns.RecruitView.cols:Reset()
            ns:Print("List columns reset to defaults.")
        end)
    end)
    W.Tooltip(resetCols, "Reset list columns", "Default column order, widths and which columns are shown, on the roster, the compact roster and the recruitment list.")
    local resetSmall = W.Button(L.panel, "Compact Windows", 150, 24)
    resetSmall:SetPoint("LEFT", resetCols, "RIGHT", 8, 0)
    resetSmall:SetScript("OnClick", function() O:ResetCompactWindows() end)
    W.Tooltip(resetSmall, "Reset compact windows", "Puts the compact roster and the recruiting bar back in their starting place and size.")
    L:Space(6)

    L:Header("About")
    self.syncStatus = L:Text("", "GameFontHighlightSmall", 6)
    y = L:Row(32)
    local syncNow = W.Button(L.panel, "Sync Now", 110, 24)
    syncNow:SetPoint("TOPLEFT", 18, y)
    syncNow:SetScript("OnClick", function()
        ns.Comm:Report()
        local started = ns.Sync:Exchange(true)
        ns:Print(started and "Comparing data with guildmates now." or "A sync just ran; it repeats automatically every few minutes.")
        O:Refresh()
    end)
    W.Tooltip(syncNow, "Sync now", "Compares your data with guildmates running the addon. It also happens by itself every few minutes.")
    local open = W.Button(L.panel, "Open Guild Manager", 170, 24)
    open:SetPoint("LEFT", syncNow, "RIGHT", 8, 0)
    open:SetScript("OnClick", function() ns.UI:OpenTab(ns.UI.TAB_ROSTER) end)
    L:Text("|cffffd100Commands|r\n"
        .. "|cffffffff/ngm|r open or close     |cffffffff/ngm compact|r compact roster     |cffffffff/ngm mini|r recruiting bar\n"
        .. "|cffffffff/ngm find <text>|r search the roster     |cffffffff/ngm polls|r polls     |cffffffff/ngm sync|r sync now\n"
        .. "|cffffffff/ngm diag|r troubleshooting     |cffffffff/ngm help|r every command", "GameFontHighlightSmall")
    L:Finish()
end

-- Compact roster and recruiting bar back to their starting place and size.
function O:ResetCompactWindows()
    local s = ns.DB:Settings()
    if s.compact then s.compact.pos, s.compact.size = nil, nil end
    s.miniPos = nil
    local CR, MR = ns.CompactRoster, ns.RecruitMini
    if CR.frame then
        local c = CR:Settings()
        CR.frame:SetSize(c.size.w, c.size.h)
        CR:RestorePosition()
    end
    if MR.frame then MR:RestorePosition() end
    ns:Print("Compact roster and recruiting bar positions reset.")
end

------------------------------------------------------------------------
-- Recruiting page
------------------------------------------------------------------------
function O:BuildRecruiting()
    local outer, L = NewPage("recruiting", "Recruiting", "Saved for the guild you're in. Messages and searching are on the Recruitment tab.")
    self.recruitNoGuild = L:Text("|cffff8080Join a guild to change these settings.|r")

    L:Header("/who Window")
    self.whoWhisperCheck = L:Check("Recruitment whisper button on /who results",
        "A button on each player in the game's /who search that sends them your recruitment whisper.",
        function(on) ns.WhoWhisper:SetEnabled(on) end)
    L:Space(4)

    L:Header("Auto-Invite")
    self.autoCheck = L:Check("Invite when they reply with a keyword",
        "Only replies from players you whispered from the addon are checked.", function(on)
            local r = ns.Recruit:Settings()
            if r then r.autoInvite = on end
            RecruitChanged()
        end)
    self.confirmCheck = L:Check("Ask me first (one-click Invite popup)",
        "Needed on clients that only allow guild invites from a click.", function(on)
            local r = ns.Recruit:Settings()
            if r then r.inviteMode = on and "confirm" or "auto" end
            RecruitChanged()
        end)
    L:Text("|cffffd100Keywords|r  |cff9d9d9d(whole words, any case)|r", "GameFontHighlightSmall", 4)
    self.keywordBoxes = WordBoxes(L, 24, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.keywords[i] = text end
        RecruitChanged()
    end)
    L:Space(4)

    L:Header("Do Not Whisper")
    self.dnwCheck = L:Check("Add people to the Do Not Whisper list",
        "When someone you whispered replies with one of these words, nobody in the guild whispers or invites them again.",
        function(on)
            local r = ns.Recruit:Settings()
            if r then r.dnwEnabled = on end
            RecruitChanged()
        end)
    L:Text("|cffffd100Words|r  |cff9d9d9d(whole words, any case)|r", "GameFontHighlightSmall", 4)
    self.dnwBoxes = WordBoxes(L, 32, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.dnwWords[i] = text end
        RecruitChanged()
    end)
    local y = L:Row(30)
    self.dnwCount = L.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.dnwCount:SetPoint("TOPLEFT", 26, y - 5)
    local view = W.Button(L.panel, "View List", 100, 22)
    view:SetPoint("TOPLEFT", 290, y)
    view:SetScript("OnClick", function(btn) ns.RecruitView:ShowDNWMenu(btn) end)
    W.Tooltip(view, "Do Not Whisper list", "Shared with everyone in the guild using the addon. Click a name to take them off it.")
    self.dnwView = view
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- Map page
------------------------------------------------------------------------
function O:BuildMap()
    local outer, L = NewPage("map", "Map", "Guildmates on your world map, and where they see you.")
    L:Header("Guildmate Locations")
    self.shareCheck = L:Check("Share my location with guildmates",
        "Your map position goes to guildmates using the addon (never inside dungeons).",
        function(on) ns.Location:SetSharing(on) end)
    self.mapCheck = L:Check("Show guildmates on the world map",
        "Hover a dot for their roster details; click it to open their profile.",
        function(on) ns.Location:SetShowing(on) end)
    L:Space(4)

    L:Header("Dot Colors")
    self.customDotsCheck = L:Check("Custom dot colors",
        "See the colors guildmates picked, and pick your own. Off: every dot is its class color.",
        function(on) ns.Location:SetCustomDots(on) end)

    -- my dot: fill and outline swatches, a preview and a reset
    local Loc = ns.Location
    local function myColors()
        local me = ns.PlayerFullName()
        local _, cls = UnitClass and UnitClass("player")
        local fr, fg, fb = ns.ClassColor(cls)
        local fill, outline = Loc:ChosenColors(me)
        if fill then fr, fg, fb = Loc.RGB(fill) end
        local br, bg, bb = 0, 0, 0
        if outline then br, bg, bb = Loc.RGB(outline) end
        return fr, fg, fb, br, bg, bb
    end
    local y = L:Row(32)
    local panel = L.panel
    local fillLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fillLabel:SetPoint("TOPLEFT", 44, y - 4)
    fillLabel:SetText("My dot")
    self.fillSwatch = W.Swatch(panel, 18, function() local r, g, b = myColors() return r, g, b end,
        function(r, g, b) Loc:SetMyColor("fill", r, g, b) O:RefreshDot() end)
    self.fillSwatch:SetPoint("LEFT", fillLabel, "RIGHT", 8, 0)
    local outLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    outLabel:SetPoint("LEFT", self.fillSwatch, "RIGHT", 18, 0)
    outLabel:SetText("Outline")
    self.outlineSwatch = W.Swatch(panel, 18, function() return select(4, myColors()) end,
        function(r, g, b) Loc:SetMyColor("outline", r, g, b) O:RefreshDot() end)
    self.outlineSwatch:SetPoint("LEFT", outLabel, "RIGHT", 8, 0)
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
    resetDot:SetScript("OnClick", function() Loc:ResetMyColors() O:RefreshDot() end)
    W.Tooltip(resetDot, "Use class color", "Your dot goes back to your class color with a black outline.")
    self.resetDot = resetDot
    self.dotRow = { fillLabel, self.fillSwatch, outLabel, self.outlineSwatch, prevLabel, pv, resetDot }
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- Officers page
------------------------------------------------------------------------
function O:BuildOfficers()
    local outer, L = NewPage("officers", "Officers", "For ranks that can read officer notes.")
    self.officerNote = L:Text("|cffff8080Only officers can change these.|r")

    L:Header("Guild Reviews  |cff9d9d9d(whole guild)|r")
    self.reviewsCheck = L:Check("Guildmates can review the guild",
        "When off, guildmates don't see the Review Guild tab. Officers still see every review.",
        function(on)
            local ok, err = ns.DB:SetReviewsEnabled(on)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
            O:Refresh()
        end)
    L:Space(4)

    L:Header("Audit History  |cff9d9d9d(your copy)|r")
    L:Text("How long to keep the record of who changed what. Older entries are deleted.")
    local y = L:Row(30)
    self.auditRadios = {}
    for i, days in ipairs({ 30, 60, 90 }) do
        local rb = CreateFrame("CheckButton", nil, L.panel, "UIRadioButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", 20 + (i - 1) * 110, y)
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
    L:Finish()
    return outer
end

function O:Build()
    self:BuildMain()
    self.subPages = {
        { key = "recruiting", frame = self:BuildRecruiting() },
        { key = "map", frame = self:BuildMap() },
        { key = "officers", frame = self:BuildOfficers() },
    }
    ns:On("SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("BRAND_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("GUILD_SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("OFFICER_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("RECRUITS_CHANGED", function()
        if O.pages.recruiting and O.pages.recruiting:IsShown() then O:RefreshRecruiting() end
    end)
end

function O:AnyShown()
    for _, page in pairs(self.pages) do if page:IsShown() then return true end end
    return false
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function SetUsable(widget, on)
    widget:SetEnabled(on)
    widget:SetAlpha(on and 1 or 0.45)
end

function O:Refresh()
    local s = ns.DB:Settings()
    for _, logo in ipairs(self.logos or {}) do logo:Apply() end

    -- main
    self.iconButton:SetText(D:IconStyle(s.iconStyle).label)
    self.iconPreview:Apply()
    self.titleCheck:SetChecked(s.titleUseGuild and true or false)
    self.addonCountCheck:SetChecked(s.showAddonCount ~= false)
    self.communitiesCheck:SetChecked(s.communitiesButton ~= false)
    self.minimapCheck:SetChecked(not s.minimap.hide)
    for _, b in ipairs(self.clickPickers) do b:SetText(D:MinimapActionLabel(s.minimap[b.key])) end
    local st = ns.Sync.stats
    self.syncStatus:SetText(("|cffffd100Sync this session:|r %d sent, %d received, %d applied, %d waiting to send."):format(
        st.sent, st.received, st.applied, ns.Sync:QueueSize()))

    self:RefreshRecruiting()

    -- map
    self.shareCheck:SetChecked(s.shareLocation ~= false)
    self.mapCheck:SetChecked(s.showOnMap ~= false)
    self.customDotsCheck:SetChecked(s.customDots == true)
    self:RefreshDot()

    -- officers
    local officer = ns.IsOfficer()
    self.officerNote:SetShown(not officer)
    self.reviewsCheck:SetChecked(ns.DB:ReviewsEnabled())
    SetUsable(self.reviewsCheck, officer and ns.DB:Guild() ~= nil)
    for _, rb in ipairs(self.auditRadios) do
        rb:SetChecked((s.auditDays or 30) == rb.days)
        SetUsable(rb, officer)
    end
end

function O:RefreshRecruiting()
    local s = ns.DB:Settings()
    self.whoWhisperCheck:SetChecked(s.whoWhisperButton ~= false)
    local r = ns.Recruit:Settings()
    self.recruitNoGuild:SetShown(r == nil)
    for _, w in ipairs({ self.autoCheck, self.confirmCheck, self.dnwCheck, self.dnwView }) do SetUsable(w, r ~= nil) end
    for _, eb in ipairs(self.keywordBoxes) do eb:SetEnabled(r ~= nil) end
    for _, eb in ipairs(self.dnwBoxes) do eb:SetEnabled(r ~= nil) end
    if not r then
        self.dnwCount:SetText("")
        return
    end
    self.autoCheck:SetChecked(r.autoInvite)
    self.confirmCheck:SetChecked(r.inviteMode == "confirm")
    self.dnwCheck:SetChecked(r.dnwEnabled)
    for i, eb in ipairs(self.keywordBoxes) do
        if not eb:HasFocus() then eb:SetText(r.keywords[i] or "") end
    end
    for i, eb in ipairs(self.dnwBoxes) do
        if not eb:HasFocus() then eb:SetText(r.dnwWords[i] or "") end
    end
    local n = #ns.Recruit:DNWList()
    self.dnwCount:SetText(n == 1 and "1 person on the list" or (n .. " people on the list"))
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
    local main = self.panel
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(main, PANEL_NAME)
        self.category = category
        if Settings.RegisterCanvasLayoutSubcategory then
            for _, p in ipairs(self.subPages) do
                self.subcats[p.key] = Settings.RegisterCanvasLayoutSubcategory(category, p.frame, p.frame.name)
            end
        end
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(main)
        for _, p in ipairs(self.subPages) do
            p.frame.parent = PANEL_NAME
            InterfaceOptions_AddCategory(p.frame)
        end
    end
end

-- key: nil for the main page, or "recruiting", "map", "officers".
function O:Open(key)
    if not self.panel then return end
    if Settings and Settings.OpenToCategory and self.category then
        local cat = key and self.subcats[key] or self.category
        local id = cat.GetID and cat:GetID() or cat.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        local frame = key and self.pages[key] or self.panel
        -- Called twice: the first call only opens the frame on some clients.
        InterfaceOptionsFrame_OpenToCategory(frame)
        InterfaceOptionsFrame_OpenToCategory(frame)
    end
end
