--[[
    Nootropic Guild Manager - Widgets
    Small reusable builders. Since 3.0 they wear the theme (UI/Theme.lua):
    NGM Peon's colours and fonts, so the addon and the dashboard look alike.
]]
local _, ns = ...
local D = ns.Data
local W = {}
ns.Widgets = W

W.WHITE = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- Frame chrome
------------------------------------------------------------------------
-- The templates' close button calls HideUIPanel, which does nothing in
-- combat (it returns early while CheckProtectedFunctionsAllowed() is false).
-- None of our windows are UI panels, so hiding them directly is always fine.
function W.CombatSafeClose(frame)
    local close = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if close then close:SetScript("OnClick", function() frame:Hide() end) end
end

function W.SetTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    else
        if not frame._title then
            frame._title = frame:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
            frame._title:SetPoint("TOP", 0, -5)
        end
        frame._title:SetText(text)
    end
end

-- CreateFrame with a template that may not exist on every client.
function W.TryCreate(frameType, name, parent, ...)
    for i = 1, select("#", ...) do
        local template = select(i, ...)
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(frameType, name, parent)
end

-- style: nil (the main action: the theme's accent), "alt" (a secondary
-- one: neutral gray) or "bad" (deletes or undoes something: red)
function W.Button(parent, text, width, height, style)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, height or 22)
    b:SetText(text)
    ns.Theme:SkinButton(b, style)
    return b
end

-- Title and lines may be functions, worked out each time it shows (for text
-- that changes, such as a renamed tab's name).
function W.Tooltip(frame, title, ...)
    local lines = { ... }
    local function Text(v) if type(v) == "function" then return v() end return v end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Text(title))
        for _, line in ipairs(lines) do GameTooltip:AddLine(Text(line), 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.SectionHeader(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    title:SetText(ns.Theme.Upper(text))
    -- the dashboard's heading: the title, then a dashed rule to the edge
    local line = ns.Theme:Dashes(parent)
    line:SetPoint("LEFT", title, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    return title, line
end

------------------------------------------------------------------------
-- Sortable column header (Who / Guild frame style)
------------------------------------------------------------------------
function W.ColumnHeader(parent, label, width, justify)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)

    -- as the dashboard's table headers: small faint upper case, a line under
    local under = b:CreateTexture(nil, "BACKGROUND")
    local lc = ns.Theme.C.line
    ns.Theme:Paint(under, lc)
    under:SetHeight(2)
    under:SetPoint("BOTTOMLEFT", 2, 0)
    under:SetPoint("BOTTOMRIGHT", -2, 0)

    local text = b:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    text:SetText(ns.Theme.Upper(label))
    local fc = ns.Theme.C.faint
    ns.Theme:Ink(text, fc)
    b.Text = text

    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", -6, -1)
    arrow:Hide()

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:SetAllPoints(b)

    -- Narrow columns use the full width for their label (the sort arrow overlaps).
    function b:SetColumnWidth(w)
        self:SetWidth(w)
        text:ClearAllPoints()
        if w < 60 then
            text:SetPoint("LEFT", 3, 0)
            text:SetPoint("RIGHT", -3, 0)
        else
            text:SetPoint("LEFT", 8, 0)
            text:SetPoint("RIGHT", -16, 0)
        end
    end
    b:SetColumnWidth(width)

    function b:SetSortState(state) -- nil | "asc" | "desc"
        if not state then arrow:Hide() return end
        arrow:Show()
        if state == "asc" then
            arrow:SetTexCoord(0, 0.5625, 1, 0)
        else
            arrow:SetTexCoord(0, 0.5625, 0, 1)
        end
    end
    return b
end

------------------------------------------------------------------------
-- Pill (a small rounded label)
------------------------------------------------------------------------
function W.Pill(parent, height, padding)
    height = height or 16
    local p = CreateFrame("Button", nil, parent, "BackdropTemplate")
    p:SetHeight(height)
    p.padding = padding or 12
    p:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    p.Icon = p:CreateTexture(nil, "ARTWORK")
    p.Icon:SetSize(height - 4, height - 4)
    p.Icon:SetPoint("LEFT", 2, 0)
    p.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.Icon:Hide()
    p.Text = p:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    p.Text:SetPoint("CENTER", 0, 0)

    local function Fit(self)
        local w = math.ceil(self.Text:GetStringWidth())
        if self.Icon:IsShown() then
            -- icon on the left, half the usual padding after the text
            self.Text:ClearAllPoints()
            self.Text:SetPoint("LEFT", self.Icon, "RIGHT", 3, 0)
            self:SetWidth(2 + self.Icon:GetWidth() + 3 + w + math.ceil(self.padding / 2))
        else
            self.Text:ClearAllPoints()
            self.Text:SetPoint("CENTER", 0, 0)
            self:SetWidth(w + self.padding)
        end
    end

    function p:SetLabel(text)
        self.Icon:Hide()
        self.Text:SetText(text)
        ns.Theme:Fill(self, ns.Theme.C.bg1, 0.9)
        ns.Theme:EdgeColor(self, ns.Theme.C.edge, 0.9)
        self.Text:SetTextColor(0.8, 0.8, 0.8)
        Fit(self)
    end

    return p
end

------------------------------------------------------------------------
-- Class icon
------------------------------------------------------------------------
local atlasCache = {}
local function HasAtlas(name)
    if atlasCache[name] == nil then
        atlasCache[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
    end
    return atlasCache[name]
end

function W.SetClassIcon(tex, classFile)
    if classFile and classFile ~= "" then
        local atlas = "classicon-" .. classFile:lower()
        if HasAtlas(atlas) then
            tex:SetAtlas(atlas)
            return
        end
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            tex:SetTexCoord(unpack(coords))
            return
        end
    end
    tex:SetTexture(D.UNKNOWN_ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

function W.SetIcon(tex, path)
    tex:SetTexture(path or D.UNKNOWN_ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

------------------------------------------------------------------------
-- Context menus
-- items: { text, func, checked = bool|fn, radio, isTitle, divider, disabled, submenu,
--          tooltip = { title, text } }
------------------------------------------------------------------------
local function Resolve(v)
    if type(v) == "function" then return v() end
    return v
end

local function BuildModern(desc, items)
    for _, it in ipairs(items) do
        if it.divider then
            desc:CreateDivider()
        elseif it.isTitle then
            desc:CreateTitle(it.text)
        elseif it.submenu then
            local sub = desc:CreateButton(it.text)
            BuildModern(sub, it.submenu)
        elseif it.checked ~= nil then
            local isSelected = function() return Resolve(it.checked) and true or false end
            local setSelected = function() if it.func then it.func() end end
            if it.radio then
                desc:CreateRadio(it.text, isSelected, setSelected)
            else
                desc:CreateCheckbox(it.text, isSelected, setSelected)
            end
        else
            local b = desc:CreateButton(it.text, function() if it.func then it.func() end end)
            if it.disabled and b.SetEnabled then b:SetEnabled(false) end
            if it.tooltip and b.SetTooltip then
                b:SetTooltip(function(tooltip)
                    tooltip:AddLine(it.tooltip.title)
                    tooltip:AddLine(it.tooltip.text, 1, 1, 1, true)
                end)
            end
        end
    end
end

local legacyDropdown
local function ShowLegacy(items)
    if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then return end
    legacyDropdown = legacyDropdown or CreateFrame("Frame", "NootropicGMDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(legacyDropdown, function(_, level, menuList)
        for _, it in ipairs(menuList or items) do
            if not it.divider then
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.text
                info.isTitle = it.isTitle
                info.disabled = it.disabled
                info.notCheckable = it.checked == nil
                if it.checked ~= nil then
                    info.checked = Resolve(it.checked)
                    info.isNotRadio = not it.radio
                    info.keepShownOnClick = not it.radio
                end
                if it.func then info.func = function() it.func() end end
                if it.tooltip then
                    info.tooltipTitle, info.tooltipText = it.tooltip.title, it.tooltip.text
                    info.tooltipOnButton = true
                end
                if it.submenu then
                    info.hasArrow = true
                    info.menuList = it.submenu
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, legacyDropdown, "cursor", 0, 0)
end

function W.ShowMenu(owner, items)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root) BuildModern(root, items) end)
    else
        ShowLegacy(items)
    end
end

------------------------------------------------------------------------
-- Result bar, like the character panel's skill bars: the common-stat-bar
-- frame behind, the common-stat-bar-blue fill trimmed by its mask. The fill
-- is greyed and tinted, so SetStatusBarColor gives any color with the
-- game's shading. Clients without that art get a plain bordered bar.
--   local holder = W.StatBar(parent, height)
--   holder.Bar:SetValue(0.5); holder.Bar:SetStatusBarColor(r, g, b)
------------------------------------------------------------------------
local function HasAtlasArt(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function W.StatBar(parent, height)
    if HasAtlasArt("common-stat-bar-BG") and HasAtlasArt("common-stat-bar-blue") then
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetHeight(height)
        bar:SetMinMaxValues(0, 1)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("common-stat-bar-BG")
        bg:SetAllPoints()
        -- a bright fill tinted with the row's color...
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local fill = bar:GetStatusBarTexture()
        fill:SetDrawLayer("BORDER")
        -- ...with the skill bar's own fill, greyed, laid over it as a light
        -- sheen so the game's shading shows through
        local sheen = bar:CreateTexture(nil, "BORDER", nil, 1)
        sheen:SetAtlas("common-stat-bar-blue")
        sheen:SetDesaturated(true)
        sheen:SetBlendMode("ADD")
        sheen:SetAlpha(0.35)
        sheen:SetAllPoints(fill)
        if HasAtlasArt("common-stat-bar-Mask") and bar.CreateMaskTexture then
            local mask = bar:CreateMaskTexture()
            mask:SetAtlas("common-stat-bar-Mask", false)
            mask:SetAllPoints()
            fill:AddMaskTexture(mask)
            sheen:AddMaskTexture(mask)
        end
        bar.Bar = bar -- the holder is the bar itself
        return bar
    end
    -- plain bar
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetHeight(height)
    bg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local bar = CreateFrame("StatusBar", nil, bg)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bg.Bar = bar
    return bg
end

------------------------------------------------------------------------
-- Popups
------------------------------------------------------------------------
local function PopupEditBox(dialog)
    return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

-- Never reassign StaticPopupDialogs itself: that taints a Blizzard global and
-- breaks the Escape key (ADDON_ACTION_FORBIDDEN SpellStopCasting). Adding our
-- own entries to the existing table is fine.

StaticPopupDialogs.NOOTROPICGM_INPUT = {
    text = "%s",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        data = data or self.data
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText(data and data.default or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        data = data or self.data
        local eb = PopupEditBox(self)
        if data and data.callback and eb then data.callback(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(eb, data)
        local dialog = eb:GetParent()
        data = data or dialog.data
        if data and data.callback then data.callback(eb:GetText()) end
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(eb)
        eb:GetParent():Hide()
    end,
}

StaticPopupDialogs.NOOTROPICGM_CONFIRM = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        data = data or self.data
        if data and data.callback then data.callback() end
    end,
}

function W.Prompt(text, default, callback, maxLetters)
    StaticPopupDialogs.NOOTROPICGM_INPUT.maxLetters = maxLetters or 32
    StaticPopup_Show("NOOTROPICGM_INPUT", text, nil, { default = default, callback = callback })
end

function W.Confirm(text, callback)
    StaticPopup_Show("NOOTROPICGM_CONFIRM", text, nil, { callback = callback })
end

------------------------------------------------------------------------
-- Scrolling multi-line text editor (Blizzard's input scroll frame when
-- available). Anchor the returned frame; its EditBox width follows it.
------------------------------------------------------------------------

function W.ScrollEditor(parent, maxLetters)
    local ok, frame = pcall(CreateFrame, "ScrollFrame", nil, parent, "InputScrollFrameTemplate")
    local box
    if ok and frame and frame.EditBox then
        box = frame.EditBox
        if frame.CharCount then frame.CharCount:Hide() end
    else
        frame = CreateFrame("ScrollFrame", nil, parent, "BackdropTemplate")
        frame:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        frame:SetBackdropColor(0, 0, 0, 0.5)
        box = CreateFrame("EditBox", nil, frame)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        frame:SetScrollChild(box)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, box:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 20)))
        end)
        frame:SetScript("OnMouseDown", function() box:SetFocus() end)
    end
    box:SetFontObject("NGMFontText")
    if maxLetters then box:SetMaxLetters(maxLetters) end
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame:HookScript("OnSizeChanged", function(self, w) box:SetWidth(math.max(20, (w or self:GetWidth()) - 18)) end)
    frame.EditBox = box
    return frame, box
end

------------------------------------------------------------------------
-- Secure overlay: lets a click on `host` run a protected action (a slash
-- command such as /gmotd or /who, or a click on a Blizzard button) through
-- the game's secure action system. Addon code can't call those functions
-- directly.
--
-- The secure button is parented to UIParent and placed over `host` by screen
-- coordinates. It is never anchored to our frames: the game refuses to anchor
-- protected frames to addon frames, and anchoring would make our own windows
-- protected too. A small watcher keeps it lined up with `host` (window moved,
-- resized or scrolled), and everything is hidden during combat, when the game
-- forbids moving protected frames.
--
--   W.SecureOverlay(host, { macro = function() return "/cmd ..." or nil end,
--                           click = "BlizzardButtonName", post = function() end })
------------------------------------------------------------------------
local overlays = {}
local watcher

local function SecureTemplateAvailable()
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo("SecureActionButtonTemplate") ~= nil
    end
    return true
end

-- Puts the overlay exactly over its host (screen coordinates), or hides it.
local function Place(b)
    if InCombatLockdown() then return end
    local host = b.host
    local left, bottom, width, height = host:GetLeft(), host:GetBottom(), host:GetWidth(), host:GetHeight()
    local usable = host:IsVisible() and (not host.IsEnabled or host:IsEnabled()) and left and bottom
    if not usable then
        if b:IsShown() then b:Hide() end
        b.placed = nil
        return
    end
    local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y, w, h = left * scale, bottom * scale, width * scale, height * scale
    local p = b.placed
    if not (p and p[1] == x and p[2] == y and p[3] == w and p[4] == h) then
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        b:SetSize(w, h)
        b.placed = { x, y, w, h }
    end
    -- Stay above the host every time, not just when it moves: clicking a
    -- top-level window raises it (and its buttons), which would otherwise
    -- leave the host on top, catching the click instead of us.
    local strata, level = host:GetFrameStrata(), host:GetFrameLevel() + 10
    if b:GetFrameStrata() ~= strata then b:SetFrameStrata(strata) end
    if b:GetFrameLevel() ~= level then b:SetFrameLevel(level) end
    if not b:IsShown() then b:Show() end
end

local function EnsureWatcher()
    if watcher then return end
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function(_, event)
        for _, b in ipairs(overlays) do
            if event == "PLAYER_REGEN_DISABLED" then
                -- still allowed at this moment; the lockdown starts right after
                b:Hide()
                b.placed = nil
            else
                Place(b)
            end
        end
    end)
    -- follows the hosts (a window being dragged) only while one is on
    -- screen: with none showing it stops itself, and a host showing again
    -- starts it (SecureOverlay), so nothing runs while the windows are shut
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.1 then return end
        elapsed = 0
        if InCombatLockdown() then return end
        local any = false
        for _, b in ipairs(overlays) do
            Place(b)
            if b.host:IsVisible() then any = true end
        end
        if not any then self:Hide() end
    end)
end

function W.SecureOverlay(host, opts)
    if not SecureTemplateAvailable() then return nil end
    local ok, b = pcall(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return nil end
    b.host = host
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:Hide()
    if opts.click then
        b:SetAttribute("type", "click")
        b:SetAttribute("clickbutton", _G[opts.click])
    else
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "")
    end
    b:SetScript("PreClick", function(self)
        if InCombatLockdown() or not opts.macro then return end
        self:SetAttribute("macrotext", opts.macro() or "")
    end)
    local lastPost = 0
    b:SetScript("PostClick", function()
        if GetTime() - lastPost < 0.5 then return end -- down + up count once
        lastPost = GetTime()
        if opts.post then opts.post() end
    end)
    b:SetScript("OnEnter", function()
        if host.LockHighlight then host:LockHighlight() end
        local fn = host:GetScript("OnEnter")
        if fn then fn(host) end
    end)
    b:SetScript("OnLeave", function()
        if host.UnlockHighlight then host:UnlockHighlight() end
        local fn = host:GetScript("OnLeave")
        if fn then fn(host) end
    end)

    b.Update = function() Place(b) end
    for _, script in ipairs({ "OnShow", "OnHide", "OnEnable", "OnDisable", "OnSizeChanged" }) do
        if host:HasScript(script) then host:HookScript(script, b.Update) end
    end
    if host:HasScript("OnShow") then host:HookScript("OnShow", function() if watcher then watcher:Show() end end) end
    overlays[#overlays + 1] = b
    host.secure = b
    EnsureWatcher()
    Place(b)
    return b
end
