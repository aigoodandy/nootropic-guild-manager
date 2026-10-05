--[[
    Nootropic Guild Manager - Icon picker
    A grid of every icon the game's macro icon menu offers (the same lists
    the macro window reads), used to choose a tag's icon. The Search box
    finds icons by the names of spells and items that use them (see Search
    below); the Paste box takes an icon found outside the game: its name,
    file number or a Wowhead link.
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
    f:SetSize(GRID_W + 52, 488)
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

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Choose an Icon")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Search box: icons used by spells or items with these words in their name
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 22, -48)
    searchLabel:SetText("Search")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(300, 20)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetScript("OnTextChanged", function() ns.Debounce("iconsearch", 0.15, function() IP:ApplySearch() end) end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    W.Tooltip(search, "Search icons", "Finds the icons of spells and items whose names have every word you type, like \"fire bolt\" or \"murloc\".",
        "Item types work too: sword, plate, potion, herb...")
    self.searchBox = search

    -- Paste box: an icon found outside the game (name, file number or link)
    local pasteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pasteLabel:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -18)
    pasteLabel:SetText("Paste")
    local paste = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    paste:SetSize(208, 20)
    paste:SetPoint("LEFT", search, "LEFT", 0, 0)
    paste:SetPoint("TOP", pasteLabel, "TOP", 0, 4)
    paste:SetAutoFocus(false)
    paste:SetMaxLetters(200)
    paste:SetScript("OnTextChanged", function() IP:UpdatePaste() end)
    paste:SetScript("OnEnterPressed", function() IP:UsePasted() end)
    paste:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    W.Tooltip(paste, "Paste an icon", "An icon name (inv_misc_head_murloc_01), a file number (134169) or a Wowhead icon link.")
    self.pasteBox = paste

    local preview = f:CreateTexture(nil, "ARTWORK")
    preview:SetSize(28, 28)
    preview:SetPoint("LEFT", paste, "RIGHT", 10, 0)
    preview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.pastePreview = preview

    local use = W.Button(f, "Use", 60, 22)
    use:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    use:SetScript("OnClick", function() IP:UsePasted() end)
    self.useButton = use

    self.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.count:SetPoint("TOPLEFT", 20, -108)
    self.indexStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.indexStatus:SetPoint("TOPRIGHT", -36, -108)

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 18, -124)
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

    self.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hint:SetPoint("BOTTOMLEFT", 22, 24)
    self.hint:SetPoint("RIGHT", cancel, "LEFT", -10, 0)
    self.hint:SetJustifyH("LEFT")
    return f
end

------------------------------------------------------------------------
-- Paste box
------------------------------------------------------------------------
-- What was pasted -> a file number or texture path to try (nil if empty).
-- Takes  inv_misc_head_murloc_01  /  Interface\Icons\INV_...  /  134169  /
-- wowhead.com/icon=134169/...  /  .../icons/large/inv_..._01.jpg
function IP.ParsePasted(text)
    text = ns.Trim(text or "")
    if text == "" then return nil end
    local id = text:match("[?&/]icon=(%d+)") or text:match("^(%d+)$")
    if id then return tonumber(id) end
    text = text:gsub("[?#].*$", "")           -- link extras
    text = text:gsub("%.%a%a%a%a?$", "")      -- .blp / .jpg / .png
    text = text:gsub("/", "\\")
    if text:lower():find("^interface\\") then return text end -- a full game path
    local name = text:match("([^\\]+)$") -- the last part of a link, or just a name
    if not name or name:find("[^%w_%-]") then return nil end
    return "Interface\\Icons\\" .. name
end

-- Does this icon exist in this version of the game? Returns the icon to
-- save (a file number when the game can tell us one) or nil.
function IP:Resolve(icon)
    if not icon then return nil end
    if type(icon) == "string" and GetFileIDFromPath then
        local ok, fid = pcall(GetFileIDFromPath, icon)
        if ok then
            if fid then return fid end
            return nil
        end
    end
    -- older clients: SetTexture says whether it loaded (when it says anything)
    self.probe = self.probe or self.frame:CreateTexture(nil, "BACKGROUND")
    self.probe:Hide()
    local loaded = self.probe:SetTexture(icon)
    if loaded == false then return nil end
    return icon
end

function IP:UpdatePaste()
    local text = self.pasteBox:GetText()
    local parsed = self.ParsePasted(text)
    local icon = self:Resolve(parsed)
    self.pasted = icon
    self.pastePreview:SetTexture(icon or D.UNKNOWN_ICON)
    self.pastePreview:SetDesaturated(icon == nil)
    self.useButton:SetEnabled(icon ~= nil)
    if ns.Trim(text) == "" then
        self.hint:SetText("Click an icon to use it.")
    elseif icon then
        self.hint:SetText("|cff66ff66Found.|r Click Use (or press Enter).")
    else
        self.hint:SetText("|cffff5555That icon isn't in this version of the game.|r")
    end
end

function IP:UsePasted()
    if self.pasted then
        self.pasteBox:ClearFocus()
        self:Choose(self.pasted)
    end
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
        b:SetScript("OnEnter", function(self) IP:ShowIconTooltip(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
-- Search: the game knows every spell's and item's icon, but icons have no
-- names of their own. The first time the picker opens in a session, the
-- addon reads through the game's spells (name and icon) and items (type,
-- such as "Sword" or "Potion", and icon) a little each frame, and keeps
-- what it finds in memory (never saved):
--   names[icon]  up to MAX_NAMES spell names that use it (for the tooltip)
--   words[icon]  everything searchable about it, lowercase
-- Item names aren't asked for: the server would have to send each one.
------------------------------------------------------------------------
local MAX_SPELL_ID = 600000
local MAX_ITEM_ID = 250000
local MAX_NAMES = 8
local MAX_WORDS = 600 -- characters kept per icon
local FRAME_BUDGET = 6 -- milliseconds of scanning per frame

IP.names, IP.words = {}, {}

local function SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then return info.name, info.iconID end
        return nil
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        return name, icon
    end
end

local function ItemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    local _, itemType, subType, _, icon = fn(id)
    return icon, itemType, subType
end

local function AddWords(icon, text)
    if not icon or not text or text == "" then return end
    local w = IP.words[icon]
    text = text:lower()
    if not w then
        IP.words[icon] = text
    elseif #w < MAX_WORDS and not w:find(text, 1, true) then
        IP.words[icon] = w .. "\n" .. text
    end
end

local function AddName(icon, name)
    if not icon or not name or name == "" then return end
    local list = IP.names[icon]
    if not list then
        list = {}
        IP.names[icon] = list
    end
    if #list < MAX_NAMES then
        for _, n in ipairs(list) do if n == name then return end end
        list[#list + 1] = name
    end
    AddWords(icon, name)
end

function IP:StartIndex()
    if self.indexing or self.indexed then return end
    self.indexing = true
    local spellId, itemId = 1, 1
    local driver = self.indexDriver or CreateFrame("Frame")
    self.indexDriver = driver
    local lastShown = 0
    driver:SetScript("OnUpdate", function()
        local stop = debugprofilestop() + FRAME_BUDGET
        while debugprofilestop() < stop do
            if spellId <= MAX_SPELL_ID then
                local ok, name, icon = pcall(SpellInfo, spellId)
                if ok and name then AddName(icon, name) end
                spellId = spellId + 1
            elseif itemId <= MAX_ITEM_ID then
                local ok, icon, itemType, subType = pcall(ItemInfo, itemId)
                if ok and icon then
                    AddWords(icon, subType)
                    AddWords(icon, itemType)
                end
                itemId = itemId + 1
            else
                driver:SetScript("OnUpdate", nil)
                IP.indexing, IP.indexed = false, true
                IP:UpdateIndexStatus()
                if IP.frame and IP.frame:IsShown() and IP.searchBox:GetText() ~= "" then IP:ApplySearch() end
                return
            end
        end
        -- progress, and fresh results while someone is searching
        local now = GetTime()
        if now - lastShown > 0.5 then
            lastShown = now
            IP.progress = (spellId + itemId) / (MAX_SPELL_ID + MAX_ITEM_ID)
            IP:UpdateIndexStatus()
            if IP.frame and IP.frame:IsShown() and IP.searchBox:GetText() ~= "" then IP:ApplySearch() end
        end
    end)
end

function IP:UpdateIndexStatus()
    if not self.indexStatus then return end
    if self.indexing then
        self.indexStatus:SetText(("Indexing spells and items... %d%%"):format(math.floor((self.progress or 0) * 100)))
    else
        self.indexStatus:SetText("")
    end
end

-- Shows these icons in the grid.
function IP:ShowIcons(icons)
    local rows = {}
    for i = 1, #icons, COLS do
        local r = {}
        for j = 0, COLS - 1 do r[#r + 1] = icons[i + j] end
        rows[#rows + 1] = { icons = r }
    end
    self.shown = icons
    self.scrollBox:SetDataProvider(CreateDataProvider(rows))
end

-- Filters the grid by the search box (every word must match).
function IP:ApplySearch()
    if not self.frame then return end
    local all = self:Icons()
    local text = ns.Trim(self.searchBox:GetText() or ""):lower()
    if text == "" then
        self:ShowIcons(all)
        self.count:SetText(("%d icons"):format(#all))
        return
    end
    local terms = {}
    for word in text:gmatch("%S+") do terms[#terms + 1] = word end
    local out, words = {}, self.words
    for _, icon in ipairs(all) do
        local w = words[icon]
        if w then
            local ok = true
            for _, t in ipairs(terms) do
                if not w:find(t, 1, true) then ok = false break end
            end
            if ok then out[#out + 1] = icon end
        end
    end
    self:ShowIcons(out)
    self.count:SetText(("%d of %d icons match"):format(#out, #all) .. (self.indexing and "  |cff9d9d9d(still indexing)|r" or ""))
end

function IP:ShowIconTooltip(button)
    local icon = button.icon
    if not icon then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("|T%s:40:40:0:0:64:64:5:59:5:59|t"):format(tostring(icon)))
    local names = self.names[icon]
    if names and #names > 0 then
        GameTooltip:AddLine("Used by: " .. table.concat(names, ", ") .. (#names >= MAX_NAMES and "..." or ""), 1, 1, 1, true)
    elseif self.indexing then
        GameTooltip:AddLine("Still indexing spells and items.", 0.7, 0.7, 0.7)
    end
    if type(icon) == "number" then GameTooltip:AddLine("Icon " .. icon, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
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
    self.searchBox:SetText("")
    self:ShowIcons(icons)
    self.count:SetText(("%d icons"):format(#icons))
    self.pasteBox:SetText("")
    self:UpdatePaste()
    self:StartIndex()
    self:UpdateIndexStatus()
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
