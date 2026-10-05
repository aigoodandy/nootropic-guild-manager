--[[
    Nootropic Guild Manager - Form pieces (Insights forms)
    Shared by the stat, poll and goal forms so they look alike:
      FK.Section(parent, text)          a gold heading with a line after it
      FK.Segment(parent, width, options, get, set)   a 2-4 way switch
      FK.LayoutPicker(parent, get, set) five small picture buttons
      FK.FilterChips(parent, width, box, onChange)   filters as removable
                                         chips, + Add filter, Edit as text
      FK.Description(parent, width, max) a description box with a counter
      FK.Form(panel, opts)               the two-page form shell (poll, goal)
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local FK = {}
ns.FormKit = FK

local GOLD = { 1, 0.82, 0 }

-- A gold heading with a thin line running to `right` (a frame's right edge).
function FK.Section(parent, text, right)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", right or parent, "RIGHT", -8, 0)
    fs.Line = line
    return fs
end

local function Box(frame, r, g, b, a)
    frame:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    frame:SetBackdropColor(r or 0.1, g or 0.09, b or 0.07, a or 0.9)
    frame:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
end

------------------------------------------------------------------------
-- Segment: options = { { key, label }, ... }; get() -> key; set(key)
------------------------------------------------------------------------
function FK.Segment(parent, width, options, get, set)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width, 24)
    Box(f, 0.05, 0.05, 0.05, 0.8)
    local n = #options
    local each = (width - 4) / n
    f.buttons = {}
    for i, o in ipairs(options) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(each, 20)
        b:SetPoint("LEFT", 2 + (i - 1) * each, 0)
        b.Sel = b:CreateTexture(nil, "BACKGROUND")
        b.Sel:SetAllPoints()
        b.Sel:SetColorTexture(0.55, 0.4, 0.1, 0.6)
        b:SetHighlightTexture(W.WHITE)
        b:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.12)
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Text:SetPoint("CENTER")
        b.Text:SetText(o.label)
        b.key = o.key
        b:SetScript("OnClick", function(self)
            if self.disabledKey then return end
            set(self.key)
            f:Refresh()
        end)
        f.buttons[i] = b
    end
    -- isEnabled(key) (optional): greys out choices you can't make
    function f:Refresh(isEnabled)
        self.isEnabled = isEnabled or self.isEnabled
        local current = get()
        for _, b in ipairs(self.buttons) do
            local on = b.key == current
            local usable = not self.isEnabled or self.isEnabled(b.key)
            b.disabledKey = not usable
            b.Sel:SetShown(on)
            if not usable then
                b.Text:SetTextColor(0.45, 0.45, 0.45)
            elseif on then
                b.Text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            else
                b.Text:SetTextColor(0.85, 0.8, 0.7)
            end
        end
    end
    return f
end

------------------------------------------------------------------------
-- Layout picker: five small picture buttons, the chosen one lit
------------------------------------------------------------------------
local function Strip(b, w, h, x, y, point)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.85, 0.75, 0.5)
    t:SetSize(w, h)
    t:SetPoint(point or "TOPLEFT", x, y)
    return t
end

local function Dot(b, size, x, y, point)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    t:SetVertexColor(0.85, 0.75, 0.5)
    t:SetSize(size, size)
    t:SetPoint(point or "CENTER", x or 0, y or 0)
    return t
end

local PICTURES = {
    barspie = function(b) Strip(b, 12, 3, 5, -6); Strip(b, 8, 3, 5, -11); Strip(b, 5, 3, 5, -16); Dot(b, 9, 7, 0) end,
    bars    = function(b) Strip(b, 20, 3, 5, -5); Strip(b, 14, 3, 5, -10); Strip(b, 9, 3, 5, -15) end,
    pie     = function(b) Dot(b, 16) end,
    columns = function(b) Strip(b, 4, 14, 7, 4, "BOTTOMLEFT"); Strip(b, 4, 9, 13, 4, "BOTTOMLEFT"); Strip(b, 4, 5, 19, 4, "BOTTOMLEFT") end,
    number  = function(b)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText("%")
        fs:SetTextColor(0.85, 0.75, 0.5)
    end,
}

function FK.LayoutPicker(parent, get, set)
    local f = CreateFrame("Frame", nil, parent)
    local layouts = ns.ChartLayouts.LAYOUTS
    f:SetSize(#layouts * 34 - 4, 40)
    f.buttons = {}
    for i, l in ipairs(layouts) do
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(30, 24)
        b:SetPoint("TOPLEFT", (i - 1) * 34, 0)
        Box(b, 0.12, 0.1, 0.08, 0.9)
        b:SetHighlightTexture(W.WHITE)
        b:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.12)
        PICTURES[l.key](b)
        b.key = l.key
        b:SetScript("OnClick", function(self)
            set(self.key)
            f:Refresh()
        end)
        W.Tooltip(b, l.label)
        f.buttons[i] = b
    end
    f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.Name:SetPoint("TOPLEFT", 0, -27)
    function f:Refresh()
        local current = get() or "barspie"
        for _, b in ipairs(self.buttons) do
            local on = b.key == current
            b:SetBackdropBorderColor(on and 1 or 0.55, on and 0.82 or 0.45, on and 0 or 0.25, 1)
            b:SetBackdropColor(on and 0.3 or 0.12, on and 0.24 or 0.1, on and 0.08 or 0.08, 0.9)
        end
        self.Name:SetText(ns.ChartLayouts.Label(current))
    end
    return f
end

------------------------------------------------------------------------
-- Filter chips. The filter text lives in `box` (an EditBox, shown instead
-- of the chips in "Edit as text" mode); chips are its words.
------------------------------------------------------------------------
-- Splits filter text into words, keeping quotes ("tag:\"world pvp\"").
function FK.SplitFilter(text)
    local out, buf, inQuote = {}, {}, false
    for i = 1, #(text or "") do
        local ch = text:sub(i, i)
        if ch == '"' then
            inQuote = not inQuote
            buf[#buf + 1] = ch
        elseif ch:match("%s") and not inQuote then
            if #buf > 0 then out[#out + 1] = table.concat(buf); buf = {} end
        else
            buf[#buf + 1] = ch
        end
    end
    if #buf > 0 then out[#out + 1] = table.concat(buf) end
    return out
end

local FIELD_NAMES = { class = "Class", race = "Race", role = "Role", rank = "Rank", prof = "Profession",
    tag = "Tag", zone = "Zone", spec = "Spec", name = "Name", note = "Note", main = "Main" }
local IS_NAMES = { main = "Mains", alt = "Alts", addon = "Using the addon", online = "Online now" }

local function Title(s)
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- "class:\"warrior\"" -> "Class: Warrior", "level>=20" -> "Level 20+", "-is:alt" -> "Not alts"
function FK.FilterLabel(word)
    local neg = word:sub(1, 1) == "-" and #word > 1
    local w = neg and word:sub(2) or word
    local label
    local lv, op, n = w:match("^(%a+)([<>=:]+)(%d+)$")
    if lv and (lv == "level" or lv == "lvl") then
        n = tonumber(n)
        if op == ">=" then label = ("Level %d+"):format(n)
        elseif op == ">" then label = ("Level %d+"):format(n + 1)
        elseif op == "<" then label = ("Below level %d"):format(n)
        elseif op == "<=" then label = ("Level %d or less"):format(n)
        else label = ("Level %d"):format(n) end
    else
        local key, value = w:match("^(%a+):(.+)$")
        value = value and value:gsub('"', "")
        if key == "is" and IS_NAMES[value] then
            label = IS_NAMES[value] .. ((value == "main" or value == "alt") and " only" or "")
        elseif key and FIELD_NAMES[key] then
            label = FIELD_NAMES[key] .. ": " .. Title(value)
        else
            label = '"' .. w:gsub('"', "") .. '"'
        end
    end
    if neg then label = "Not " .. label:sub(1, 1):lower() .. label:sub(2) end
    return label
end

------------------------------------------------------------------------
-- Form shell (the poll and goal forms): a header with a Settings | preview
-- switch on its line, two pages, and Delete ... Cancel Save along the bottom.
-- opts: { title, previewLabel, saveText, onSave, onCancel, onDelete, onPage(page) }
-- form.settings is the settings page's content; it scrolls, and is as tall
-- as form:FitSettings(lowest) makes it. form.preview is a plain frame.
------------------------------------------------------------------------
function FK.Form(panel, opts)
    local c = CreateFrame("Frame", nil, panel)
    c:SetAllPoints()
    c:Hide()
    local form = { frame = c }

    local title, line = W.SectionHeader(c, opts.title)
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    form.header = title

    local scroll = W.TryCreate("ScrollFrame", nil, c, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -36)
    scroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -26, 44)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)
    form.scroll, form.settings = scroll, content

    local preview = CreateFrame("Frame", nil, c)
    preview:SetPoint("TOPLEFT", 10, -36)
    preview:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 44)
    preview:Hide()
    form.preview = preview
    form.pages = { settings = scroll, preview = preview }

    form.seg = FK.Segment(c, 220,
        { { key = "settings", label = "Settings" }, { key = "preview", label = opts.previewLabel or "Look & preview" } },
        function() return form.page end, function(key) form:ShowPage(key) end)
    form.seg:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -8)
    form.seg:SetFrameLevel(c:GetFrameLevel() + 5)

    -- bottom bar
    local bar = c:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(1, 0.82, 0, 0.18)
    bar:SetHeight(1)
    bar:SetPoint("BOTTOMLEFT", 10, 42)
    bar:SetPoint("BOTTOMRIGHT", -10, 42)
    local save = W.Button(c, opts.saveText or SAVE or "Save", 100, 22)
    save:SetPoint("BOTTOMRIGHT", -12, 12)
    save:SetScript("OnClick", function() opts.onSave() end)
    local cancel = W.Button(c, CANCEL or "Cancel", 90, 22)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() opts.onCancel() end)
    local flip = W.Button(c, "", 110, 22)
    flip:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    flip:SetScript("OnClick", function() form:ShowPage(form.page == "settings" and "preview" or "settings") end)
    local del = W.Button(c, DELETE or "Delete", 90, 22)
    del:SetPoint("BOTTOMLEFT", 12, 12)
    del:SetScript("OnClick", function() if opts.onDelete then opts.onDelete() end end)
    del:Hide()
    form.saveBtn, form.flipBtn, form.deleteBtn = save, flip, del
    local err = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    err:SetPoint("RIGHT", flip, "LEFT", -10, 0)
    err:SetPoint("LEFT", c, "LEFT", 112, 0)
    err:SetJustifyH("RIGHT")
    err:SetWordWrap(false)
    err:SetTextColor(1, 0.35, 0.35)
    form.err = err

    -- page: "settings" or "preview"
    function form:ShowPage(page)
        self.page = page
        for key, frame in pairs(self.pages) do frame:SetShown(key == page) end
        self.seg:Refresh()
        self.flipBtn:SetText(page == "settings" and "Preview  >" or "<  Settings")
        if page == "settings" then self:FitSettings() end
        if opts.onPage then opts.onPage(page) end
    end

    -- The settings page's height: down to `lowest` (remembered), so it scrolls.
    function form:FitSettings(lowest)
        self.lowest = lowest or self.lowest
        local function Fit()
            local top, bottom = content:GetTop(), self.lowest and self.lowest:GetBottom()
            if top and bottom then content:SetHeight(math.max(10, top - bottom + 12)) end
        end
        Fit()
        C_Timer.After(0, Fit)
    end

    return form
end

-- "Description (optional)" with a "12 / 200" counter, over a two-line box.
-- Returns the label (to place) and the edit box.
function FK.Description(parent, width, max)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText("Description  |cff9d9d9d(optional)|r")
    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("BOTTOMRIGHT", label, "BOTTOMLEFT", width, 0)
    local frame, box = W.ScrollEditor(parent, max)
    frame:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -4)
    frame:SetSize(width, 38)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(width - 18)
    local function Update() count:SetText(("%d / %d"):format(#(box:GetText() or ""), max)) end
    box:HookScript("OnTextChanged", Update)
    box.UpdateCount = Update
    return label, box
end

function FK.FilterChips(parent, width, box, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 24)
    f.chips = {}
    f.box = box
    box:SetParent(f)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", 6, 0)
    box:SetWidth(width - 8)
    box:Hide()
    box:HookScript("OnTextChanged", function(_, user) if user and onChange then onChange() end end)

    local function NewChip()
        local c = CreateFrame("Button", nil, f, "BackdropTemplate")
        c:SetHeight(20)
        Box(c, 0.16, 0.14, 0.1, 0.95)
        c:SetHighlightTexture(W.WHITE)
        c:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.1)
        c.Text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.Text:SetPoint("LEFT", 8, 0)
        c.X = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        c.X:SetPoint("RIGHT", -6, 0)
        return c
    end

    -- "+ Add filter"
    local add = NewChip()
    add:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    add.Text:SetText("|cffffd100+ Add filter|r")
    add.X:SetText("")
    add:SetWidth(math.ceil(add.Text:GetStringWidth()) + 18)
    add:SetScript("OnClick", function(self) ns.PollsView:FilterMenu(self, box, function() f:Refresh(); if onChange then onChange() end end) end)
    f.add = add

    -- "Edit as text" / "Show as chips"
    local toggle = CreateFrame("Button", nil, f)
    toggle:SetSize(90, 16)
    toggle.Text = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggle.Text:SetPoint("RIGHT")
    toggle:SetScript("OnClick", function()
        f.textMode = not f.textMode
        f:Refresh()
    end)
    f.toggle = toggle

    f.Matches = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    function f:SetTextMode(on) self.textMode = on; self:Refresh() end

    -- Lays the chips out in rows; returns nothing (f's height follows).
    function f:Refresh()
        local words = FK.SplitFilter(box:GetText() or "")
        for _, c in ipairs(self.chips) do c:Hide() end
        local x, y = 0, 0
        if self.textMode then
            box:Show()
            self.add:Hide()
            y = -24
        else
            box:Hide()
            for i, word in ipairs(words) do
                local c = self.chips[i]
                if not c then
                    c = NewChip()
                    c:SetScript("OnClick", function(chip)
                        local list = FK.SplitFilter(box:GetText() or "")
                        table.remove(list, chip.index)
                        box:SetText(table.concat(list, " "))
                        f:Refresh()
                        if onChange then onChange() end
                    end)
                    W.Tooltip(c, "Click to remove this filter")
                    self.chips[i] = c
                end
                c.index = i
                c.Text:SetText(FK.FilterLabel(word))
                c.X:SetText("x")
                c:SetWidth(math.ceil(c.Text:GetStringWidth()) + 30)
                if x > 0 and x + c:GetWidth() > width then x, y = 0, y - 24 end
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", x, y)
                c:Show()
                x = x + c:GetWidth() + 4
            end
            local a = self.add
            if x > 0 and x + a:GetWidth() > width then x, y = 0, y - 24 end
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", x, y)
            a:Show()
            y = y - 24
        end
        self.Matches:ClearAllPoints()
        self.Matches:SetPoint("TOPLEFT", 0, y - 4)
        self.toggle:ClearAllPoints()
        self.toggle:SetPoint("TOPRIGHT", 0, y - 3)
        self.toggle.Text:SetText(self.textMode and "|cff66bbffShow as chips|r" or "|cff66bbffEdit as text|r")
        self:SetHeight(-y + 22)
    end
    return f
end
