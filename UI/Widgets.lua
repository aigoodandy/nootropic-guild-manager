--[[
    Nootropic Guild Manager - Widgets
    Small reusable builders that use Blizzard's own textures and templates so
    the addon looks like part of the default interface.
]]
local _, ns = ...
local D = ns.Data
local W = {}
ns.Widgets = W

W.WHITE = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- Frame chrome
------------------------------------------------------------------------
function W.SetTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    else
        if not frame._title then
            frame._title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame._title:SetPoint("TOP", 0, -5)
        end
        frame._title:SetText(text)
    end
end

function W.SetPortrait(frame, texture)
    if frame.SetPortraitToAsset and pcall(frame.SetPortraitToAsset, frame, texture) then return end
    local p = frame.portrait or frame.Portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
    if p then
        if SetPortraitToTexture then SetPortraitToTexture(p, texture) else p:SetTexture(texture) end
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

function W.Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, height or 22)
    b:SetText(text)
    return b
end

-- Blizzard's red expand / condense arrow button (the same family as the red
-- close X). kind: "expand" or "condense". Uses the game's atlas when the
-- client has it, otherwise the older bigger/smaller panel buttons.
function W.SizeButton(parent, kind, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    local atlas = kind == "expand" and "RedButton-Expand" or "RedButton-Condense"
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if hasAtlas then
        b:SetNormalAtlas(atlas)
        b:SetPushedAtlas(atlas .. "-Pressed")
        b:SetDisabledAtlas(atlas .. "-Disabled")
        b:SetHighlightAtlas("RedButton-Highlight", "ADD")
    else
        local base = kind == "expand" and "Interface\\Buttons\\UI-Panel-BiggerButton-" or "Interface\\Buttons\\UI-Panel-SmallerButton-"
        b:SetNormalTexture(base .. "Up")
        b:SetPushedTexture(base .. "Down")
        b:SetHighlightTexture(base .. "Highlight", "ADD")
    end
    return b
end

function W.Tooltip(frame, title, ...)
    local lines = { ... }
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.SectionHeader(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.22)
    line:SetHeight(1)
    line:SetPoint("LEFT", title, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    return title, line
end

------------------------------------------------------------------------
-- Sortable column header (Who / Guild frame style)
------------------------------------------------------------------------
function W.ColumnHeader(parent, label, width, justify)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)

    local TEX = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs"
    local l = b:CreateTexture(nil, "BACKGROUND")
    l:SetTexture(TEX); l:SetTexCoord(0, 0.078125, 0, 0.75)
    l:SetSize(5, 24); l:SetPoint("TOPLEFT")
    local r = b:CreateTexture(nil, "BACKGROUND")
    r:SetTexture(TEX); r:SetTexCoord(0.90625, 0.96875, 0, 0.75)
    r:SetSize(4, 24); r:SetPoint("TOPRIGHT")
    local m = b:CreateTexture(nil, "BACKGROUND")
    m:SetTexture(TEX); m:SetTexCoord(0.078125, 0.90625, 0, 0.75)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    b.Text = text

    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", -6, -1)
    arrow:Hide()

    b:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", 2, 3)
    hl:SetPoint("BOTTOMRIGHT", -2, -3)

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
-- Tag pill
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
    p.Text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

    -- Tag icon and name in the tag's color. active == false draws it dimmed (toggles).
    function p:SetTag(tag, active)
        self.tag = tag
        self.Text:SetText(tag.name)
        self.Icon:SetTexture(D:TagIcon(tag))
        self.Icon:Show()
        local r, g, b = D:TagColor(tag.color)
        if active == false then
            self:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
            self:SetBackdropBorderColor(0.32, 0.32, 0.32, 0.9)
            self.Text:SetTextColor(0.55, 0.55, 0.55)
            self.Icon:SetDesaturated(true)
            self.Icon:SetAlpha(0.6)
        else
            self:SetBackdropColor(r * 0.28, g * 0.28, b * 0.28, 0.92)
            self:SetBackdropBorderColor(r, g, b, 0.85)
            self.Text:SetTextColor(math.min(1, r * 0.45 + 0.55), math.min(1, g * 0.45 + 0.55), math.min(1, b * 0.45 + 0.55))
            self.Icon:SetDesaturated(false)
            self.Icon:SetAlpha(1)
        end
        Fit(self)
    end

    function p:SetLabel(text)
        self.tag = nil
        self.Icon:Hide()
        self.Text:SetText(text)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        self:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
        self.Text:SetTextColor(0.8, 0.8, 0.8)
        Fit(self)
    end

    return p
end

-- A tag's icon with a thin border in the tag's color (roster Tags column).
function W.TagIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    f:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 1 })
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetPoint("TOPLEFT", 1, -1)
    f.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function f:SetTag(tag)
        self.tag = tag
        self.Icon:SetTexture(D:TagIcon(tag))
        local r, g, b = D:TagColor(tag.color)
        self:SetBackdropBorderColor(r, g, b, 1)
    end
    return f
end

------------------------------------------------------------------------
-- Star rating (raid-marker star)
------------------------------------------------------------------------
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

function W.Stars(parent, size, interactive, onChange)
    local gap = 2
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size * 5 + gap * 4, size)
    f.value = 0
    f.stars = {}

    function f:Paint(n)
        for i = 1, 5 do
            local t = self.stars[i].tex
            if i <= n then
                t:SetDesaturated(false); t:SetAlpha(1)
            else
                t:SetDesaturated(true); t:SetAlpha(0.22)
            end
        end
    end
    function f:SetValue(n)
        self.value = n or 0
        self:Paint(self.value)
    end

    for i = 1, 5 do
        local s = CreateFrame("Button", nil, f)
        s:SetSize(size, size)
        s:SetPoint("LEFT", (i - 1) * (size + gap), 0)
        s.tex = s:CreateTexture(nil, "ARTWORK")
        s.tex:SetAllPoints()
        s.tex:SetTexture(STAR)
        if interactive then
            s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            s:SetScript("OnEnter", function() f:Paint(i) end)
            s:SetScript("OnLeave", function() f:Paint(f.value) end)
            s:SetScript("OnClick", function(_, button)
                local v = (button == "RightButton" or f.value == i) and 0 or i
                f:SetValue(v)
                if onChange then onChange(v) end
            end)
        else
            s:EnableMouse(false)
        end
        f.stars[i] = s
    end

    f:SetValue(0)
    return f
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
-- items: { text, func, checked = bool|fn, radio, isTitle, divider, disabled, submenu }
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
-- Opens the game's color picker. onChange(r, g, b) runs while the color is
-- dragged; Cancel restores (and reports) the starting color.
function W.PickColor(r, g, b, onChange)
    local picker = ColorPickerFrame
    if type(picker) ~= "table" then return end
    local r0, g0, b0 = r, g, b
    local function apply()
        local nr, ng, nb = picker:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function cancel() onChange(r0, g0, b0) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = apply, cancelFunc = cancel })
    else
        picker:Hide()
        picker.hasOpacity, picker.opacityFunc = false, nil
        picker.previousValues = { r, g, b }
        picker.func, picker.cancelFunc = apply, cancel
        picker:SetColorRGB(r, g, b)
        if ShowUIPanel then ShowUIPanel(picker) else picker:Show() end
    end
end

-- A small color square that opens the color picker when clicked.
function W.Swatch(parent, size, getColor, onChange)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    b:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    function b:Update()
        local r, g, bl = getColor()
        self:SetBackdropColor(r, g, bl, 1)
    end
    b:SetScript("OnClick", function()
        local r, g, bl = getColor()
        W.PickColor(r, g, bl, function(nr, ng, nb)
            onChange(nr, ng, nb)
            b:Update()
        end)
    end)
    return b
end

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
    box:SetFontObject("GameFontHighlight")
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
        b:SetFrameStrata(host:GetFrameStrata())
        b:SetFrameLevel(host:GetFrameLevel() + 10)
        b.placed = { x, y, w, h }
    end
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
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.1 then return end
        elapsed = 0
        if InCombatLockdown() then return end
        for _, b in ipairs(overlays) do Place(b) end
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
    overlays[#overlays + 1] = b
    host.secure = b
    EnsureWatcher()
    Place(b)
    return b
end
