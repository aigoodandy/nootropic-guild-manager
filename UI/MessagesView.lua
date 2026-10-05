--[[
    Nootropic Guild Manager - Custom Messages window
    Left: the messages in priority order (top wins), with on/off switches,
    New / Copy / Delete and up/down to change priority.
    Right: the selected message's filters (class, race, level, zone, guild)
    and text, with a live preview and how many players in the Recruitment
    list it applies to.
    Import / Export trade messages as plain text; Class Defaults adds back
    the built-in message for any class missing one.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local MV = {}
ns.MessagesView = MV

local WIDTH, HEIGHT = 720, 520
local LIST_W = 230
local ROW_H = 34

-- Race portraits (male and female) from the character-creation screen.
local RACE_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"
local RACE_FILE = { ["human"] = "HUMAN", ["dwarf"] = "DWARF", ["gnome"] = "GNOME", ["night elf"] = "NIGHTELF",
    ["tauren"] = "TAUREN", ["undead"] = "SCOURGE", ["troll"] = "TROLL", ["orc"] = "ORC" }
local RACE_COORDS = {
    HUMAN_MALE = { 0, 0.125, 0, 0.25 },       DWARF_MALE = { 0.125, 0.25, 0, 0.25 },
    GNOME_MALE = { 0.25, 0.375, 0, 0.25 },    NIGHTELF_MALE = { 0.375, 0.5, 0, 0.25 },
    TAUREN_MALE = { 0, 0.125, 0.25, 0.5 },    SCOURGE_MALE = { 0.125, 0.25, 0.25, 0.5 },
    TROLL_MALE = { 0.25, 0.375, 0.25, 0.5 },  ORC_MALE = { 0.375, 0.5, 0.25, 0.5 },
    HUMAN_FEMALE = { 0, 0.125, 0.5, 0.75 },   DWARF_FEMALE = { 0.125, 0.25, 0.5, 0.75 },
    GNOME_FEMALE = { 0.25, 0.375, 0.5, 0.75 }, NIGHTELF_FEMALE = { 0.375, 0.5, 0.5, 0.75 },
    TAUREN_FEMALE = { 0, 0.125, 0.75, 1 },    SCOURGE_FEMALE = { 0.125, 0.25, 0.75, 1 },
    TROLL_FEMALE = { 0.25, 0.375, 0.75, 1 },  ORC_FEMALE = { 0.375, 0.5, 0.75, 1 },
}
MV.RACE_COORDS = RACE_COORDS

-- Uses the client's race icon atlas when it has one, otherwise the classic
-- character-creation texture.
local function SetRaceIcon(tex, race, sex)
    local file = RACE_FILE[race:lower()]
    if type(C_Texture) == "table" and C_Texture.GetAtlasInfo and tex.SetAtlas then
        local s, plain = sex:lower(), race:lower():gsub(" ", "")
        for _, name in ipairs({ "raceicon-" .. (file or ""):lower() .. "-" .. s, "raceicon-" .. plain .. "-" .. s }) do
            if C_Texture.GetAtlasInfo(name) then
                tex:SetAtlas(name)
                return
            end
        end
    end
    local c = file and RACE_COORDS[file .. "_" .. sex]
    tex:SetTexture(RACE_TEXTURE)
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
end

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "NootropicGM_GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function InputBox(parent, width, maxLetters, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetFontObject("NootropicGM_GameFontHighlightSmall")
    if maxLetters then eb:SetMaxLetters(maxLetters) end
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

-- A pill that toggles on/off (gold when on).
local function Toggle(parent, text, onClick)
    local p = W.Pill(parent, 18, 14)
    p:SetLabel(text)
    function p:SetOn(on)
        self.on = on
        if on then
            self:SetBackdropColor(0.35, 0.27, 0, 0.95)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
            self.Text:SetTextColor(1, 0.92, 0.5)
        else
            self:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
            self:SetBackdropBorderColor(0.32, 0.32, 0.32, 0.9)
            self.Text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
    p:SetScript("OnClick", function(self)
        onClick(self)
        ns.PlaySound("U_CHAT_SCROLL_BUTTON")
    end)
    return p
end

local function SmallIconButton(parent, normal, pushed, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b:SetNormalTexture(normal)
    b:SetPushedTexture(pushed)
    b:SetDisabledTexture(normal)
    b:GetDisabledTexture():SetDesaturated(true)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W.Tooltip(b, tip)
    return b
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function MV:Build()
    local f = CreateFrame("Frame", "NootropicGMMessagesFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    W.SetTitle(f, "Custom Recruitment Messages")
    self.frame = f

    local intro = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetPoint("RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Messages are checked from the top down: the first one whose filters all match a player is the one they get. Players nothing matches get the Default message.")

    self:BuildList(f)
    self:BuildEditor(f)

    f:SetScript("OnShow", function() MV:Refresh() end)
    f:SetScript("OnHide", function() if MV.transfer then MV.transfer:Hide() end end)
    ns:On("MESSAGES_CHANGED", function() if f:IsShown() then MV:Refresh() end end)
    ns:On("RECRUITS_CHANGED", function() if f:IsShown() then ns.Debounce("mvmatch", 0.2, function() MV:RefreshEditorInfo() end) end end)
end

function MV:BuildList(f)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 12, -62)
    box:SetPoint("BOTTOMLEFT", 12, 70)
    box:SetWidth(LIST_W)
    box:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.4)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local scrollBox = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 4)
    local scrollBar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, item) MV:InitRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.listEmpty = box:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.listEmpty:SetPoint("CENTER")
    self.listEmpty:SetWidth(LIST_W - 30)
    self.listEmpty:SetText("No custom messages yet. Click New to make one.")

    local new = W.Button(f, "New", 58, 22)
    new:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    new:SetScript("OnClick", function()
        local rule = ns.Messages:New()
        if rule then MV:Select(rule.id) end
    end)
    local copy = W.Button(f, "Copy", 54, 22)
    copy:SetPoint("LEFT", new, "RIGHT", 2, 0)
    copy:SetScript("OnClick", function()
        local rule = MV.selected and ns.Messages:Duplicate(MV.selected)
        if rule then MV:Select(rule.id) end
    end)
    local del = W.Button(f, "Delete", 62, 22)
    del:SetPoint("LEFT", copy, "RIGHT", 2, 0)
    del:SetScript("OnClick", function()
        local rule = MV.selected and ns.Messages:Get(MV.selected)
        if not rule then return end
        W.Confirm(("Delete the custom message \"%s\"?"):format(rule.name), function()
            ns.Messages:Delete(rule.id)
            MV.selected = nil
            MV:Refresh()
        end)
    end)
    self.up = SmallIconButton(f, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down", "Higher priority")
    self.up:SetPoint("LEFT", del, "RIGHT", 4, 0)
    self.up:SetScript("OnClick", function() if MV.selected then ns.Messages:Move(MV.selected, -1) end end)
    self.down = SmallIconButton(f, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down", "Lower priority")
    self.down:SetPoint("LEFT", self.up, "RIGHT", -2, 0)
    self.down:SetScript("OnClick", function() if MV.selected then ns.Messages:Move(MV.selected, 1) end end)
    self.copyBtn, self.delBtn = copy, del

    local import = W.Button(f, "Import...", 70, 22)
    import:SetPoint("TOPLEFT", new, "BOTTOMLEFT", 0, -4)
    import:SetScript("OnClick", function() MV:ShowTransfer("import") end)
    W.Tooltip(import, "Import messages", "Paste messages someone exported (plain text) and add them to your list.")
    local export = W.Button(f, "Export...", 70, 22)
    export:SetPoint("LEFT", import, "RIGHT", 2, 0)
    export:SetScript("OnClick", function() MV:ShowTransfer("export") end)
    W.Tooltip(export, "Export messages", "Shows all your messages as plain text to copy and share.")
    local defaults = W.Button(f, "Class Defaults", 86, 22)
    defaults:SetPoint("LEFT", export, "RIGHT", 2, 0)
    defaults:SetScript("OnClick", function()
        local n = ns.Messages:AddClassDefaults()
        ns:Print(n > 0 and ("Added %d built-in class message%s."):format(n, n == 1 and "" or "s")
            or "Every class already has a message.")
    end)
    W.Tooltip(defaults, "Class default messages", "Adds the built-in message for every class that doesn't have a message of its own.")
    self.importBtn, self.exportBtn, self.defaultsBtn = import, export, defaults
end

function MV:InitRow(row, item)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
        row.Selected = row:CreateTexture(nil, "BACKGROUND")
        row.Selected:SetAllPoints()
        row.Selected:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        row.Selected:SetBlendMode("ADD")
        row.Selected:SetVertexColor(1, 0.82, 0, 0.5)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:GetHighlightTexture():SetAlpha(0.35)
        row.Num = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalLarge")
        row.Num:SetPoint("LEFT", 4, 0)
        row.Num:SetWidth(20)
        row.On = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.On:SetSize(22, 22)
        row.On:SetPoint("LEFT", 24, 0)
        row.On:SetScript("OnClick", function(self)
            if row.rule then ns.Messages:Update(row.rule.id, "enabled", self:GetChecked() and true or false) end
        end)
        W.Tooltip(row.On, "Use this message", "Untick to keep it without using it.")
        row.Name = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
        row.Name:SetPoint("TOPLEFT", 50, -4)
        row.Name:SetPoint("RIGHT", -4, 0)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.Info = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
        row.Info:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2)
        row.Info:SetPoint("RIGHT", -4, 0)
        row.Info:SetJustifyH("LEFT")
        row.Info:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.rule then MV:Select(self.rule.id) end end)
    end
    local rule = item.rule
    row.rule = rule
    row.Num:SetText(item.index)
    row.On:SetChecked(rule.enabled)
    row.Name:SetText(rule.name ~= "" and rule.name or "(no name)")
    row.Name:SetAlpha(rule.enabled and 1 or 0.5)
    row.Info:SetText(ns.Messages:Summary(rule))
    row.Selected:SetShown(rule.id == self.selected)
end

------------------------------------------------------------------------
-- Editor
------------------------------------------------------------------------
function MV:BuildEditor(f)
    local e = CreateFrame("Frame", nil, f)
    e:SetPoint("TOPLEFT", LIST_W + 26, -62)
    e:SetPoint("BOTTOMRIGHT", -14, 12)
    self.editor = e
    local EW = WIDTH - LIST_W - 40

    self.noSelection = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisable")
    self.noSelection:SetPoint("CENTER", e, "CENTER")
    self.noSelection:SetText("Select a message on the left, or click New.")

    local y = 0
    local nameLabel = Label(e, "Name")
    nameLabel:SetPoint("TOPLEFT", 0, y - 4)
    self.nameBox = InputBox(e, 220, 40)
    self.nameBox:SetPoint("TOPLEFT", 50, y)
    self.nameBox:HookScript("OnTextChanged", function(self, user)
        if user and MV.selected then ns.Messages:Update(MV.selected, "name", self:GetText()) end
    end)
    y = y - 30

    -- Class
    local classLabel = Label(e, "Class")
    classLabel:SetPoint("TOPLEFT", 0, y - 4)
    self.classButtons = {}
    for i, cls in ipairs(D.CLASSES) do
        local b = CreateFrame("Button", nil, e, "BackdropTemplate")
        b:SetSize(24, 24)
        b:SetPoint("TOPLEFT", 50 + (i - 1) * 27, y)
        b:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 1 })
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetPoint("TOPLEFT", 1, -1)
        b.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
        W.SetClassIcon(b.Icon, cls)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() MV:ToggleSet("classes", cls) end)
        W.Tooltip(b, D:ClassName(cls), "Click to include or exclude. None selected = any class.")
        b.key = cls
        self.classButtons[i] = b
    end
    y = y - 32

    -- Race (your faction's races; each shows its male and female portrait)
    local raceLabel = Label(e, "Race")
    raceLabel:SetPoint("TOPLEFT", 0, y - 8)
    self.raceButtons = {}
    for i, race in ipairs(ns.Messages:FactionRaces()) do
        local b = CreateFrame("Button", nil, e, "BackdropTemplate")
        b:SetSize(56, 30)
        b:SetPoint("TOPLEFT", 50 + (i - 1) * 62, y)
        b:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 1 })
        b.Male = b:CreateTexture(nil, "ARTWORK")
        b.Male:SetSize(26, 26)
        b.Male:SetPoint("LEFT", 2, 0)
        SetRaceIcon(b.Male, race, "MALE")
        b.Female = b:CreateTexture(nil, "ARTWORK")
        b.Female:SetSize(26, 26)
        b.Female:SetPoint("RIGHT", -2, 0)
        SetRaceIcon(b.Female, race, "FEMALE")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function()
            MV:ToggleSet("races", race:lower())
            ns.PlaySound("U_CHAT_SCROLL_BUTTON")
        end)
        W.Tooltip(b, race, "Click to include or exclude. None selected = any race.")
        b.key = race:lower()
        self.raceButtons[i] = b
    end
    y = y - 38

    -- Guild
    local guildLabel = Label(e, "Guild")
    guildLabel:SetPoint("TOPLEFT", 0, y - 3)
    self.guildToggles = {}
    local x = 50
    for _, opt in ipairs({ { "any", "Any" }, { "none", "No guild" }, { "guilded", "In a guild" } }) do
        local t = Toggle(e, opt[2], function() if MV.selected then ns.Messages:Update(MV.selected, "guild", opt[1]) end end)
        t:SetPoint("TOPLEFT", x, y)
        x = x + t:GetWidth() + 4
        t.key = opt[1]
        self.guildToggles[#self.guildToggles + 1] = t
    end
    W.Tooltip(self.guildToggles[3], "In a guild", "For players found with the Recruitment tab's Guild search.")
    y = y - 30

    -- Level and zone
    local lvlLabel = Label(e, "Level")
    lvlLabel:SetPoint("TOPLEFT", 0, y - 4)
    self.minLevel = InputBox(e, 30, 2, true)
    self.minLevel:SetPoint("TOPLEFT", 54, y)
    local to = Label(e, "to", "NootropicGM_GameFontHighlightSmall")
    to:SetPoint("LEFT", self.minLevel, "RIGHT", 6, 0)
    self.maxLevel = InputBox(e, 30, 2, true)
    self.maxLevel:SetPoint("LEFT", to, "RIGHT", 10, 0)
    -- an empty box means no limit (shown as 1 and max level once you leave it)
    local function saveLevels()
        if not MV.selected then return end
        ns.Messages:Update(MV.selected, "minLevel", tonumber(MV.minLevel:GetText()))
        ns.Messages:Update(MV.selected, "maxLevel", tonumber(MV.maxLevel:GetText()))
    end
    local function fillLevels()
        local rule = MV.selected and ns.Messages:Get(MV.selected)
        if not rule then return end
        MV.minLevel:SetText(tostring(rule.minLevel or 1))
        MV.maxLevel:SetText(tostring(rule.maxLevel or ns.Recruit:MaxLevel()))
    end
    self.minLevel:HookScript("OnEditFocusLost", fillLevels)
    self.maxLevel:HookScript("OnEditFocusLost", fillLevels)
    self.minLevel:HookScript("OnTextChanged", function(_, user) if user then saveLevels() end end)
    self.maxLevel:HookScript("OnTextChanged", function(_, user) if user then saveLevels() end end)

    local zoneLabel = Label(e, "Zone")
    zoneLabel:SetPoint("TOPLEFT", 160, y - 4)
    self.zoneBox = InputBox(e, EW - 206, 120)
    self.zoneBox:SetPoint("TOPLEFT", 200, y)
    self.zoneBox:HookScript("OnTextChanged", function(self, user)
        if user and MV.selected then ns.Messages:Update(MV.selected, "zones", self:GetText()) end
    end)
    W.Tooltip(self.zoneBox, "Zones", "Comma-separated; any part of the zone name, e.g. \"Elwynn, Westfall\". Empty = anywhere.")
    y = y - 34

    -- Message text
    local msgLabel = Label(e, "Message")
    msgLabel:SetPoint("TOPLEFT", 0, y)
    self.count = e:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.count:SetPoint("TOPRIGHT", e, "TOPRIGHT", 0, y)
    local ef, box = W.ScrollEditor(e, D.WHISPER_MAX)
    ef:SetPoint("TOPLEFT", 2, y - 16)
    ef:SetSize(EW - 6, 78)
    box:SetFontObject("NootropicGM_GameFontHighlightSmall")
    box:SetWidth(EW - 24)
    box:HookScript("OnTextChanged", function(self, user)
        if user and MV.selected then ns.Messages:Update(MV.selected, "text", (self:GetText():gsub("[\r\n]+", " "))) end
        MV:RefreshEditorInfo()
    end)
    self.textBox = box
    y = y - 102

    local tokens = e:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    tokens:SetPoint("TOPLEFT", 0, y)
    tokens:SetText("|cffffd100$name  $class  $level  $race  $zone  $guild|r are filled in for each player")
    y = y - 18

    self.preview = e:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    self.preview:SetPoint("TOPLEFT", 0, y)
    self.preview:SetWidth(EW - 4)
    self.preview:SetJustifyH("LEFT")
    self.preview:SetSpacing(2)
    y = y - 46

    self.matchInfo = e:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalSmall")
    self.matchInfo:SetPoint("TOPLEFT", 0, y)
    self.matchInfo:SetWidth(EW - 4)
    self.matchInfo:SetJustifyH("LEFT")

    self.editorWidgets = { nameLabel, self.nameBox, classLabel, raceLabel, guildLabel, lvlLabel,
        self.minLevel, to, self.maxLevel, zoneLabel, self.zoneBox, msgLabel, self.count, ef, tokens, self.preview, self.matchInfo }
    for _, b in ipairs(self.classButtons) do self.editorWidgets[#self.editorWidgets + 1] = b end
    for _, b in ipairs(self.raceButtons) do self.editorWidgets[#self.editorWidgets + 1] = b end
    for _, t in ipairs(self.guildToggles) do self.editorWidgets[#self.editorWidgets + 1] = t end
end

function MV:ToggleSet(field, key)
    local rule = self.selected and ns.Messages:Get(self.selected)
    if not rule then return end
    local set = {}
    for k, v in pairs(rule[field]) do set[k] = v end
    set[key] = not set[key] or nil
    ns.Messages:Update(rule.id, field, set)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function MV:Select(id)
    self.selected = id
    self:Refresh(true)
end

function MV:Refresh(loadTexts)
    if not self.frame then return end
    local rules = ns.Messages:Rules()
    if self.selected and not ns.Messages:Get(self.selected) then self.selected = nil end
    if not self.selected and rules[1] then
        self.selected = rules[1].id
        loadTexts = true
    end
    local items = {}
    for i, rule in ipairs(rules) do items[i] = { rule = rule, index = i } end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(items), retain)
    self.listEmpty:SetShown(#rules == 0)

    local rule, index = nil, nil
    if self.selected then rule, index = ns.Messages:Get(self.selected) end
    self.copyBtn:SetEnabled(rule ~= nil)
    self.delBtn:SetEnabled(rule ~= nil)
    self.up:SetEnabled(rule ~= nil and index > 1)
    self.down:SetEnabled(rule ~= nil and index < #rules)

    for _, w in ipairs(self.editorWidgets) do w:SetShown(rule ~= nil) end
    self.noSelection:SetShown(rule == nil)
    if not rule then return end

    if loadTexts or not self.nameBox:HasFocus() then self.nameBox:SetText(rule.name or "") end
    if loadTexts or not self.textBox:HasFocus() then self.textBox:SetText(rule.text or "") end
    if loadTexts or not self.zoneBox:HasFocus() then self.zoneBox:SetText(rule.zones or "") end
    if loadTexts or not self.minLevel:HasFocus() then self.minLevel:SetText(tostring(rule.minLevel or 1)) end
    if loadTexts or not self.maxLevel:HasFocus() then self.maxLevel:SetText(tostring(rule.maxLevel or ns.Recruit:MaxLevel())) end
    for _, b in ipairs(self.classButtons) do
        local on = rule.classes[b.key] and true or false
        b.Icon:SetDesaturated(not on and next(rule.classes) ~= nil)
        b.Icon:SetAlpha((on or not next(rule.classes)) and 1 or 0.35)
        if on then b:SetBackdropBorderColor(1, 0.82, 0, 1) else b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end
    end
    local anyRace = not next(rule.races)
    for _, b in ipairs(self.raceButtons) do
        local on = rule.races[b.key] and true or false
        for _, tex in ipairs({ b.Male, b.Female }) do
            tex:SetDesaturated(not on and not anyRace)
            tex:SetAlpha((on or anyRace) and 1 or 0.35)
        end
        if on then b:SetBackdropBorderColor(1, 0.82, 0, 1) else b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end
    end
    for _, t in ipairs(self.guildToggles) do t:SetOn((rule.guild or "any") == t.key) end
    self:RefreshEditorInfo()
end

-- Preview, character count, and which players in the list get this message.
function MV:RefreshEditorInfo()
    local rule = self.selected and ns.Messages:Get(self.selected)
    if not rule or not self.preview then return end
    local text = rule.text or ""
    self.count:SetText(("%d / %d"):format(#text, D.WHISPER_MAX))

    local list = ns.Recruit:List()
    local matches, wins, example = 0, 0, nil
    for _, p in ipairs(list) do
        if ns.Messages:Matches(rule, p) then
            matches = matches + 1
            local _, winner = ns.Messages:Pick(p)
            if winner == rule then
                wins = wins + 1
                example = example or p
            end
        end
    end
    local sample = example or { short = "Thrall", full = "Thrall", classFile = "WARRIOR", className = "Warrior", level = 42,
        race = "Orc", zone = "Durotar" }
    local out = ns.Recruit:Format(text, sample)
    self.preview:SetText(("|cffffd100Preview%s:|r "):format(example and (" for " .. example.short) or "")
        .. (out ~= "" and ("|cffff80ff" .. out .. "|r") or "|cff9d9d9d(write the message above)|r"))
    local r = ns.Recruit:Settings()
    local note = ""
    if not (r and r.useRules) then
        note = "  |cffff8080Custom messages are turned off on the Recruitment tab.|r"
    elseif not rule.enabled then
        note = "  |cffff8080This message is switched off.|r"
    elseif matches > wins then
        note = ("  |cff9d9d9d%d go to a message higher in the list.|r"):format(matches - wins)
    end
    self.matchInfo:SetText(("Matches %d player%s in your Recruitment list; %d will get this message.%s")
        :format(matches, matches == 1 and "" or "s", wins, note))
end

function MV:Toggle()
    if not self.frame then self:Build() end
    self.frame:SetShown(not self.frame:IsShown())
end

function MV:Show()
    if not self.frame then self:Build() end
    self.frame:Show()
end

------------------------------------------------------------------------
-- Import / Export (plain text)
------------------------------------------------------------------------
function MV:BuildTransfer()
    local f = self.frame
    local t = CreateFrame("Frame", nil, f, "BackdropTemplate")
    t:SetPoint("TOPLEFT", 10, -26)
    t:SetPoint("BOTTOMRIGHT", -10, 10)
    t:SetFrameLevel(f:GetFrameLevel() + 20)
    t:EnableMouse(true)
    t:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    t:SetBackdropColor(0.04, 0.04, 0.04, 0.97)
    t:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    t:Hide()
    self.transfer = t

    t.Title = t:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalLarge")
    t.Title:SetPoint("TOPLEFT", 16, -14)
    t.Help = t:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    t.Help:SetPoint("TOPLEFT", t.Title, "BOTTOMLEFT", 0, -6)
    t.Help:SetPoint("RIGHT", -16, 0)
    t.Help:SetJustifyH("LEFT")

    local ef, box = W.ScrollEditor(t)
    ef:SetPoint("TOPLEFT", 18, -66)
    ef:SetPoint("BOTTOMRIGHT", -36, 76)
    box:SetFontObject("NootropicGM_GameFontHighlightSmall")
    box:SetWidth(WIDTH - 90)
    box:HookScript("OnTextChanged", function(self, user)
        -- keep the export text intact if someone types in it
        if user and t.mode == "export" then self:SetText(t.exportText or "") self:HighlightText() end
    end)
    t.Edit, t.Box = ef, box

    t.Result = t:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    t.Result:SetPoint("BOTTOMLEFT", 18, 44)
    t.Result:SetPoint("RIGHT", -16, 0)
    t.Result:SetJustifyH("LEFT")
    t.Result:SetWordWrap(true)
    t.Result:SetMaxLines(2)

    local close = W.Button(t, CLOSE or "Close", 80, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    close:SetScript("OnClick", function() t:Hide() end)

    local add = W.Button(t, "Add to My Messages", 150, 22)
    add:SetPoint("BOTTOMLEFT", 16, 12)
    add:SetScript("OnClick", function() MV:DoImport("add") end)
    W.Tooltip(add, "Add to my messages", "Adds the pasted messages after the ones you have.")
    local replace = W.Button(t, "Replace All", 100, 22)
    replace:SetPoint("LEFT", add, "RIGHT", 4, 0)
    replace:SetScript("OnClick", function()
        W.Confirm("Delete all your custom messages and use the pasted ones instead?", function() MV:DoImport("replace") end)
    end)
    local select = W.Button(t, "Select All", 100, 22)
    select:SetPoint("BOTTOMLEFT", 16, 12)
    select:SetScript("OnClick", function() box:SetFocus() box:HighlightText() end)
    t.AddBtn, t.ReplaceBtn, t.SelectBtn = add, replace, select
end

function MV:ShowTransfer(mode)
    if not self.frame then self:Build() end
    if not self.transfer then self:BuildTransfer() end
    local t = self.transfer
    t.mode = mode
    t.Result:SetText("")
    local export = mode == "export"
    t.AddBtn:SetShown(not export)
    t.ReplaceBtn:SetShown(not export)
    t.SelectBtn:SetShown(export)
    if export then
        t.Title:SetText("Export Custom Messages")
        t.Help:SetText("Press Ctrl+C to copy this text, then paste it anywhere (a guild website, Discord, a text file). Someone else can paste it into Import.")
        t.exportText = ns.Messages:Export()
        t.Box:SetText(t.exportText)
        t.Result:SetText(("%d message%s."):format(#ns.Messages:Rules(), #ns.Messages:Rules() == 1 and "" or "s"))
    else
        t.Title:SetText("Import Custom Messages")
        t.Help:SetText("Paste exported messages here (Ctrl+V). Each one starts with \"message:\" followed by lines like classes:, races:, levels:, zones:, guild: and text:.")
        t.Box:SetText("")
    end
    self.frame:Show()
    t:Show()
    t.Box:SetFocus()
    if export then t.Box:HighlightText() end
end

function MV:DoImport(mode)
    local t = self.transfer
    local n, problems = ns.Messages:Import(t.Box:GetText(), mode)
    local msg
    if n > 0 then
        msg = ("|cff40ff40Imported %d message%s.|r"):format(n, n == 1 and "" or "s")
        local r = ns.Recruit:Settings()
        if r and not r.useRules then msg = msg .. " Tick Use custom messages on the Recruitment tab to use them." end
    else
        msg = "|cffff5555Nothing imported.|r"
    end
    if problems and #problems > 0 then
        msg = msg .. " |cffff8080" .. problems[1] .. (#problems > 1 and (" (+%d more)"):format(#problems - 1) or "") .. "|r"
    end
    t.Result:SetText(msg)
    if n > 0 then
        local rules = ns.Messages:Rules()
        self:Select(rules[#rules - n + 1].id)
    end
end
