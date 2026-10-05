--[[
    Nootropic Guild Manager - Icon picker
    A grid of every icon the game's macro icon menu offers (the same lists
    the macro window reads), used to choose a tag's icon.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local IP = {}
ns.IconPicker = IP

local COLS = 10
local SIZE = 32
local GAP = 4
local ROW_H = SIZE + GAP
local GRID_W = COLS * (SIZE + GAP)

-- Every macro icon (file ids on current clients, texture names on older ones).
function IP:Icons()
    if self.icons and #self.icons > 0 then return self.icons end
    local raw = {}
    local function Collect(fn)
        if type(fn) ~= "function" then return end
        local before = #raw
        local ok, res = pcall(fn, raw)
        -- some clients return a new table instead of filling ours
        if ok and type(res) == "table" and res ~= raw and #raw == before then
            for _, v in ipairs(res) do raw[#raw + 1] = v end
        end
    end
    Collect(GetLooseMacroIcons)
    Collect(GetLooseMacroItemIcons)
    Collect(GetMacroIcons)
    Collect(GetMacroItemIcons)
    if #raw == 0 and GetNumMacroIcons and GetMacroIconInfo then
        local ok, n = pcall(GetNumMacroIcons)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, tex = pcall(GetMacroIconInfo, i)
            if ok2 and tex then raw[#raw + 1] = tex end
        end
    end
    local out, seen = {}, {}
    local function Add(v)
        local icon = type(v) == "number" and v or D:ParseIcon(tostring(v))
        if icon and not seen[icon] then
            seen[icon] = true
            out[#out + 1] = icon
        end
    end
    for _, v in ipairs(raw) do Add(v) end
    if #out == 0 then
        -- the game gave us nothing: offer the icons the addon already knows
        for _, def in ipairs(D.DEFAULT_TAGS) do Add(def[3]) end
        for _, p in ipairs(D.PROFESSIONS) do Add(p.icon) end
        Add(D.UNKNOWN_ICON)
    end
    self.icons = out
    return out
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function IP:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "NootropicGMIconPicker", UIParent, "BackdropTemplate")
    f:SetSize(GRID_W + 52, 420)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Choose an Icon")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    self.count = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.count:SetPoint("TOPLEFT", 20, -40)

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 18, -58)
    scrollBox:SetPoint("BOTTOMLEFT", 18, 48)
    scrollBox:SetWidth(GRID_W)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Frame", function(row, item) IP:InitRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    local cancel = W.Button(f, CANCEL or "Cancel", 100, 22)
    cancel:SetPoint("BOTTOMRIGHT", -20, 18)
    cancel:SetScript("OnClick", function() f:Hide() end)

    self.hint = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    self.hint:SetPoint("BOTTOMLEFT", 22, 24)
    self.hint:SetText("Click an icon to use it.")
    return f
end

local function BuildRow(row)
    row:SetHeight(ROW_H)
    row.buttons = {}
    for i = 1, COLS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(SIZE, SIZE)
        b:SetPoint("TOPLEFT", (i - 1) * (SIZE + GAP), 0)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetAllPoints()
        b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.Selected = b:CreateTexture(nil, "OVERLAY")
        b.Selected:SetPoint("TOPLEFT", -3, 3)
        b.Selected:SetPoint("BOTTOMRIGHT", 3, -3)
        b.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.Selected:SetBlendMode("ADD")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self) IP:Choose(self.icon) end)
        row.buttons[i] = b
    end
end

function IP:InitRow(row, item)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    for i, b in ipairs(row.buttons) do
        local icon = item.icons[i]
        b.icon = icon
        if icon then
            b.Icon:SetTexture(icon)
            b.Selected:SetShown(icon == self.current)
            b:Show()
        else
            b:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------
function IP:Choose(icon)
    if not icon then return end
    local cb = self.onPick
    self.frame:Hide()
    ns.PlaySound("U_CHAT_SCROLL_BUTTON")
    if cb then cb(icon) end
end

-- onPick(icon) runs with the chosen file id or texture path.
function IP:Open(current, onPick, anchor)
    local f = self:Build()
    self.current, self.onPick = current, onPick
    local icons = self:Icons()
    local rows = {}
    for i = 1, #icons, COLS do
        local r = {}
        for j = 0, COLS - 1 do r[#r + 1] = icons[i + j] end
        rows[#rows + 1] = { icons = r }
    end
    self.count:SetText(("%d icons"):format(#icons))
    self.scrollBox:SetDataProvider(CreateDataProvider(rows))
    f:ClearAllPoints()
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    f:Raise()
    -- start at the current icon
    for i, icon in ipairs(icons) do
        if icon == current then
            local index = math.floor((i - 1) / COLS) + 1
            if self.scrollBox.ScrollToElementDataIndex then
                pcall(self.scrollBox.ScrollToElementDataIndex, self.scrollBox, index)
            end
            break
        end
    end
end

function IP:Hide()
    if self.frame then self.frame:Hide() end
end
