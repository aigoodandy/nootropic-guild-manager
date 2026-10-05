--[[
    Nootropic Guild Manager - Tags tab (officers only)
    Two lists officers manage, picked with the Tags | Kudos switch: the
    guild's tags and its kudos (both shared with everyone using the addon).
    The list is on the left; the selected one is edited on the right: name,
    icon, color, order, and Retire (kudos) or Delete (tags).
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local TV = {}
ns.TagsView = TV

local ROW_H = 26

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function IsKudos() return TV.mode == "kudos" end

-- All tags, or all kudos (retired ones too).
local function AllItems()
    if IsKudos() then return ns.Profile:KudosTypes(true) end
    return ns.DB:GetTags()
end

local function Find(id)
    if not id or id == "new" then return nil end
    for _, it in ipairs(AllItems()) do
        if it.id == id then return it end
    end
end

local function IconOf(it)
    if IsKudos() then return ns.Profile.KudosIcon(it) end
    return D:TagIcon(it)
end

-- Kudos given per type in the last 90 days, guild-wide: typeId -> count,
-- and for one type: member -> count.
local function KudosGiven(forType)
    local byType, byMember = {}, {}
    local cutoff = ns.DB:Now() - ns.Profile.KUDOS_DAYS * 86400
    for member, types in pairs(ns.Profile.KudosIndex()) do
        for typeId, times in pairs(types) do
            for _, t in ipairs(times) do
                if t >= cutoff then
                    byType[typeId] = (byType[typeId] or 0) + 1
                    if typeId == forType then byMember[member] = (byMember[member] or 0) + 1 end
                end
            end
        end
    end
    return byType, byMember
end

local function Plural(n, one, many)
    return n == 1 and ("1 " .. one) or (n .. " " .. many)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
local function SmallIconButton(parent, normal, pushed, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:SetNormalTexture(normal)
    b:SetPushedTexture(pushed)
    b:SetDisabledTexture(normal)
    b:GetDisabledTexture():SetDesaturated(true)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W.Tooltip(b, tip)
    return b
end

-- The Tags | Kudos switch: two halves of one box, the chosen one lit gold.
local function BuildSwitch(page, frame)
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetSize(152, 22)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 76, -32)
    box:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    local buttons = {}
    for i, mode in ipairs({ "tags", "kudos" }) do
        local b = CreateFrame("Button", nil, box)
        b:SetSize(75, 20)
        b:SetPoint("LEFT", 1 + (i - 1) * 75, 0)
        b.Sel = b:CreateTexture(nil, "BACKGROUND")
        b.Sel:SetAllPoints()
        b.Sel:SetColorTexture(0.55, 0.4, 0.1, 0.55)
        b:SetHighlightTexture(W.WHITE)
        b:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.12)
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.Text:SetPoint("CENTER")
        b.Text:SetText(mode == "tags" and "Tags" or "Kudos")
        b:SetScript("OnClick", function()
            if TV.mode == mode then return end
            TV.mode, TV.sel, TV.draft = mode, nil, nil
            ns.PlaySound("IG_CHARACTER_INFO_TAB")
            TV:Refresh()
        end)
        buttons[mode] = b
    end
    local divider = box:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.55, 0.45, 0.25, 1)
    divider:SetSize(1, 20)
    divider:SetPoint("LEFT", 76, 0)
    TV.switch = buttons
    return box
end

function TV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page = page
    page:SetScript("OnShow", function() TV:Refresh() end)
    TV.mode = "tags"

    local switch = BuildSwitch(page, frame)

    local new = W.Button(page, "+ New Tag", 110, 22)
    new:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    new:SetScript("OnClick", function() TV:Select("new") end)
    self.newBtn = new

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", switch, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", new, "LEFT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    self.hint = hint

    local inset = frame.Inset
    self:BuildList(page, inset)
    self:BuildEditor(page, inset)

    ns:On("TAGS_CHANGED", function() if page:IsVisible() then TV:Refresh() end end)
    ns:On("KUDOS_CHANGED", function()
        if page:IsVisible() and IsKudos() then ns.Debounce("tagsview", 0.2, function() TV:Refresh() end) end
    end)
    ns:On("ROSTER_UPDATED", function()
        if page:IsVisible() then ns.Debounce("tagsview", 0.2, function() TV:Refresh() end) end
    end)
end

------------------------------------------------------------------------
-- List (left)
------------------------------------------------------------------------
function TV:BuildList(page, inset)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 4)
    list:SetWidth(300)
    self.list = list

    self.counter = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.counter:SetPoint("TOPLEFT", 8, -6)
    self.colLabel = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.colLabel:SetPoint("TOPRIGHT", -22, -6)

    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, -22)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, item) TV:InitRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    -- a thin line between the list and the editor
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.18)
    line:SetWidth(1)
    line:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    line:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)

    self.emptyText = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.emptyText:SetPoint("LEFT", 12, 0)
    self.emptyText:SetPoint("RIGHT", -12, 0)
end

local function BuildRow(row)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetColorTexture(1, 1, 1, 0.03)
    row.Sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Sel:SetAllPoints()
    row.Sel:SetColorTexture(1, 0.75, 0.2, 0.16)
    row.SelEdge = row:CreateTexture(nil, "ARTWORK")
    row.SelEdge:SetColorTexture(1, 0.82, 0, 0.8)
    row.SelEdge:SetPoint("TOPLEFT")
    row.SelEdge:SetPoint("BOTTOMLEFT")
    row.SelEdge:SetWidth(2)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.35)

    row.Pill = W.Pill(row, 20, 16)
    row.Pill:SetPoint("LEFT", 10, 0)
    row.Pill:EnableMouse(false)

    row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.Count:SetPoint("RIGHT", -8, 0)

    -- the "Retired (n)" fold
    row.FoldIcon = row:CreateTexture(nil, "ARTWORK")
    row.FoldIcon:SetSize(14, 14)
    row.FoldIcon:SetPoint("LEFT", 10, 0)
    row.FoldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.FoldText:SetPoint("LEFT", row.FoldIcon, "RIGHT", 6, 0)

    -- kudos rows show their description
    row:SetScript("OnEnter", function(self)
        local it = self.item and self.item.obj
        if not (it and it.desc and it.desc ~= "") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(it.name)
        ns.Profile.AddKudosDesc(GameTooltip, it)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self, button)
        local item = self.item
        if not item then return end
        if item.fold then
            TV.showRetired = not TV.showRetired
            TV:Refresh()
            return
        end
        if button == "RightButton" then
            TV:RowMenu(self, item)
            return
        end
        TV:Select(item.obj.id)
    end)
end

function TV:InitRow(row, item)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    row.item = item
    local fold = item.fold
    row.Pill:SetShown(not fold)
    row.Count:SetShown(not fold)
    row.FoldIcon:SetShown(fold)
    row.FoldText:SetShown(fold)
    if fold then
        row.Stripe:Hide()
        row.Sel:Hide()
        row.SelEdge:Hide()
        row.FoldIcon:SetTexture(TV.showRetired and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        row.FoldText:SetText(("Retired (%d)"):format(item.count))
        return
    end
    local selected = TV.sel == item.obj.id
    row.Stripe:SetShown(item.stripe)
    row.Sel:SetShown(selected)
    row.SelEdge:SetShown(selected)
    row.Pill:SetTag(item.obj, not item.obj.retired)
    row.Count:SetText(item.countText)
end

function TV:RowMenu(row, item)
    local it, kudos = item.obj, IsKudos()
    local items = { { text = it.name, isTitle = true } }
    items[#items + 1] = { text = "Edit", func = function() TV:Select(it.id) end }
    items[#items + 1] = { text = "Move Up", disabled = item.first, func = function() TV:Move(it, -1) end }
    items[#items + 1] = { text = "Move Down", disabled = item.last, func = function() TV:Move(it, 1) end }
    if not kudos then
        items[#items + 1] = { text = "Show in Roster", func = function() TV:ShowInRoster(it) end }
    end
    items[#items + 1] = { divider = true }
    if kudos then
        items[#items + 1] = { text = it.retired and "Bring Back" or "Retire", func = function() TV:Remove(it) end }
    else
        items[#items + 1] = { text = "Delete", func = function() TV:Remove(it) end }
    end
    W.ShowMenu(row, items)
end

------------------------------------------------------------------------
-- Editor (right)
------------------------------------------------------------------------
local function Label(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

function TV:BuildEditor(page, inset)
    local ed = CreateFrame("Frame", nil, page)
    ed:SetPoint("TOPLEFT", self.list, "TOPRIGHT", 18, -4)
    ed:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -10, 6)
    self.editor = ed

    -- big icon in the chosen color; click to pick another
    local icon = CreateFrame("Button", nil, ed, "BackdropTemplate")
    icon:SetSize(52, 52)
    icon:SetPoint("TOPLEFT", 0, -2)
    icon:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 2 })
    icon.Tex = icon:CreateTexture(nil, "ARTWORK")
    icon.Tex:SetPoint("TOPLEFT", 2, -2)
    icon.Tex:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.Tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnClick", function(self) TV:PickIcon(self) end)
    W.Tooltip(icon, "Choose an icon", "Any icon from the macro icon menu.")
    self.iconButton = icon

    self.title = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    self.title:SetPoint("RIGHT", ed, "RIGHT", 0, 0)
    self.title:SetJustifyH("LEFT")
    self.title:SetWordWrap(false)
    self.preview = W.Pill(ed, 20, 16)
    self.preview:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -5)
    self.preview:EnableMouse(false)
    self.previewIcon = W.TagIcon(ed, 20)
    self.previewIcon:SetPoint("LEFT", self.preview, "RIGHT", 10, 0)
    W.Tooltip(self.previewIcon, "Roster column", "How this tag looks in the roster's Tags column.")
    self.previewIcon:EnableMouse(true)
    self.sub = ed:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.preview, "BOTTOMLEFT", 0, -4)

    -- Name
    local nameLabel = Label(ed, "Name")
    nameLabel:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16)
    local name = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
    name:SetHeight(20)
    name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    name:SetPoint("RIGHT", ed, "RIGHT", -4, 0)
    name:SetAutoFocus(false)
    name:SetMaxLetters(D.MAX_TAG_LENGTH)
    name:SetScript("OnTextChanged", function(self, userInput)
        if TV.filling or not userInput or not TV.draft then return end
        TV.draft.name = self:GetText()
        TV.err = nil
        TV:UpdateEditor()
    end)
    name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); TV:Save() end)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.nameBox = name

    -- Description (kudos only): shown in tooltips
    local descLabel = Label(ed, "Description")
    descLabel:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -10)
    self.descLabel = descLabel
    self.descCount = ed:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.descCount:SetPoint("RIGHT", ed, "RIGHT", -4, 0)
    self.descCount:SetPoint("BOTTOM", descLabel, "BOTTOM")
    local descFrame, desc = W.ScrollEditor(ed, D.MAX_KUDOS_DESC)
    descFrame:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 4, -6)
    descFrame:SetPoint("RIGHT", ed, "RIGHT", -8, 0)
    descFrame:SetHeight(48)
    desc:SetFontObject("GameFontHighlightSmall")
    desc:HookScript("OnTextChanged", function(self, userInput)
        if TV.filling or not userInput or not TV.draft then return end
        TV.draft.desc = (self:GetText():gsub("[\r\n]+", " "))
        TV.err = nil
        TV:UpdateEditor()
    end)
    self.descFrame, self.descBox = descFrame, desc

    -- Icon / Color / Order (below the description for kudos, the name for tags)
    local iconLabel = Label(ed, "Icon")
    self.iconLabel = iconLabel
    local change = W.Button(ed, "Change...", 90, 22)
    change:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -4)
    change:SetScript("OnClick", function(self) TV:PickIcon(self) end)

    local colorLabel = Label(ed, "Color")
    colorLabel:SetPoint("LEFT", iconLabel, "LEFT", 102, 0)
    local color = W.Button(ed, "", 120, 22)
    color:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -4)
    color.Arrow = color:CreateTexture(nil, "OVERLAY")
    color.Arrow:SetSize(18, 18)
    color.Arrow:SetPoint("RIGHT", -4, 0)
    color.Arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    color:SetScript("OnClick", function(self)
        W.ShowColorMenu(self, function() return TV.draft and TV.draft.color end, function(i)
            if not TV.draft then return end
            TV.draft.color = i
            TV:UpdateEditor()
        end)
    end)
    self.colorButton = color

    local orderLabel = Label(ed, "Order")
    orderLabel:SetPoint("LEFT", colorLabel, "LEFT", 132, 0)
    self.orderLabel = orderLabel
    local up = SmallIconButton(ed, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down", "Move up")
    up:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", -2, -4)
    up:SetScript("OnClick", function() local it = TV:Selected(); if it then TV:Move(it, -1) end end)
    local down = SmallIconButton(ed, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down", "Move down")
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    down:SetScript("OnClick", function() local it = TV:Selected(); if it then TV:Move(it, 1) end end)
    self.upBtn, self.downBtn = up, down

    -- Who has it / top this period
    local infoLabel = Label(ed, "")
    infoLabel:SetPoint("TOPLEFT", change, "BOTTOMLEFT", 0, -18)
    self.infoLabel = infoLabel
    local roster = CreateFrame("Button", nil, ed)
    roster:SetSize(110, 16)
    roster:SetPoint("LEFT", infoLabel, "RIGHT", 10, 0)
    roster.Text = roster:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roster.Text:SetPoint("LEFT")
    roster.Text:SetText("|cff66bbffShow in Roster|r")
    roster:SetScript("OnClick", function() local it = TV:Selected(); if it then TV:ShowInRoster(it) end end)
    self.rosterLink = roster
    local info = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", infoLabel, "BOTTOMLEFT", 0, -6)
    info:SetPoint("RIGHT", ed, "RIGHT", -4, 0)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    info:SetSpacing(3)
    self.info = info

    -- Save / Undo ... Retire
    local save = W.Button(ed, SAVE or "Save", 90, 22)
    save:SetPoint("BOTTOMLEFT", 0, 0)
    save:SetScript("OnClick", function() TV:Save() end)
    self.saveBtn = save
    local undo = W.Button(ed, "Undo", 90, 22)
    undo:SetPoint("LEFT", save, "RIGHT", 6, 0)
    undo:SetScript("OnClick", function() TV:Undo() end)
    self.undoBtn = undo
    local remove = W.Button(ed, "Retire", 100, 22)
    remove:SetPoint("BOTTOMRIGHT", 0, 0)
    remove:SetScript("OnClick", function() local it = TV:Selected(); if it then TV:Remove(it) end end)
    self.removeBtn = remove

    local line = ed:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.18)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", save, "TOPLEFT", 0, 8)
    line:SetPoint("RIGHT", ed, "RIGHT")

    self.errorText = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.errorText:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 6)
    self.errorText:SetPoint("RIGHT", ed, "RIGHT")
    self.errorText:SetJustifyH("LEFT")
    self.errorText:SetTextColor(1, 0.35, 0.35)

    self.edEmpty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.edEmpty:SetPoint("CENTER", ed, "CENTER")
end

------------------------------------------------------------------------
-- Selection and the draft being edited
------------------------------------------------------------------------
function TV:Selected() return Find(self.sel) end

function TV:Select(id)
    self.sel = id
    self.draft = nil
    self:Refresh()
    if id == "new" then self.nameBox:SetFocus() end
end

-- Starts editing the selection fresh (its saved name, color and icon).
function TV:ResetDraft()
    local it = self:Selected()
    if it then
        self.draft = { name = it.name, color = it.color, desc = it.desc or "" }
    else
        self.draft = { name = "", color = D:NextColor(#AllItems()), desc = "" }
    end
    self.err = nil
    self.filling = true
    self.nameBox:SetText(self.draft.name)
    self.descBox:SetText(self.draft.desc)
    self.filling = false
    self.nameBox:ClearFocus()
    self.descBox:ClearFocus()
end

function TV:DisplayIcon()
    local d, it = self.draft, self:Selected()
    if d and d.icon then return d.icon end
    return it and IconOf(it) or D.UNKNOWN_ICON
end

function TV:Dirty()
    local d, it = self.draft, self:Selected()
    if not d then return false end
    if not it then return ns.Trim(d.name) ~= "" end
    if IsKudos() and ns.Trim(d.desc or "") ~= (it.desc or "") then return true end
    return ns.Trim(d.name) ~= it.name or d.color ~= it.color or (d.icon ~= nil and d.icon ~= IconOf(it))
end

function TV:PickIcon(anchor)
    if not self.draft then return end
    ns.IconPicker:Open(self:DisplayIcon(), function(chosen)
        if not self.draft then return end
        self.draft.icon = chosen
        self:UpdateEditor()
    end, anchor)
end

function TV:Save()
    local d = self.draft
    if not (d and self:Dirty()) then return end
    local it, kudos = self:Selected(), IsKudos()
    local result, err
    if kudos then
        local PF = ns.Profile
        if it then
            result, err = PF:UpdateKudos(it.id, d.name, d.color, d.icon)
            if not err then result, err = PF:SetKudosDesc(it.id, d.desc) end
        else
            result, err = PF:CreateKudos(d.name, d.color, d.icon or D.UNKNOWN_ICON, d.desc)
        end
    elseif it then
        result, err = ns.DB:UpdateTag(it.id, ns.Trim(d.name), d.color, d.icon)
    else
        result, err = ns.DB:CreateTag(d.name, d.color, d.icon)
    end
    if err then
        self.err = err
        self:UpdateEditor()
        return
    end
    if not it and type(result) == "table" and result.id then self.sel = result.id end
    self.draft = nil
    self:Refresh()
end

function TV:Undo()
    if self.sel == "new" then
        self.sel, self.draft = nil, nil -- back to the first one
        self:Refresh()
        return
    end
    self:ResetDraft()
    self:UpdateEditor()
end

-- Moves within its own group (active or retired kudos).
function TV:Move(it, delta)
    local _, err
    if IsKudos() then _, err = ns.Profile:MoveKudos(it.id, delta) else _, err = ns.DB:MoveTag(it.id, delta) end
    if err then ns:Print("|cffff5555" .. err .. "|r") end
end

function TV:Remove(it)
    if IsKudos() then
        local _, err = ns.Profile:SetKudosRetired(it.id, not it.retired)
        if err then
            self.err = err
            self:UpdateEditor()
        elseif not it.retired then
            self.showRetired = true -- so it doesn't just vanish
        end
        return
    end
    W.Confirm(("Delete the tag \"%s\"?\nIt will be removed from every member."):format(it.name), function()
        ns.DB:DeleteTag(it.id)
    end)
end

function TV:ShowInRoster(it)
    ns.UI:ShowRosterWithSearch(('tag:"%s"'):format(it.name:lower()))
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
-- The list gets a bit under half the window; the editor the rest.
function TV:OnResize(width)
    if self.list then self.list:SetWidth(math.max(250, math.min(380, math.floor((width - 40) * 0.45)))) end
end

function TV:Refresh()
    if self.page and not ns.IsOfficer() then
        self.page:Hide() -- officers only; the tab is hidden for everyone else
        return
    end
    if not self.page then return end
    local kudos = IsKudos()
    for mode, b in pairs(self.switch) do
        local on = mode == self.mode
        b.Sel:SetShown(on)
        b.Text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
        b.Text:SetTextColor(on and 1 or 0.6, on and 1 or 0.55, on and 1 or 0.45)
    end
    self.newBtn:SetText(kudos and "+ New Kudos" or "+ New Tag")
    self.hint:SetText(kudos and "Given anonymously from profiles. Retired kudos can't be given."
        or "Members tag themselves from their profile.")
    self.colLabel:SetText(kudos and "Last 90 days" or "Members")

    local all = AllItems()
    local inGuild = ns.DB:Guild() ~= nil
    -- keep the selection if it still exists, else the first one (or a new one)
    if self.sel ~= "new" and not Find(self.sel) then
        self.sel = nil
        self.draft = nil
        for _, it in ipairs(all) do
            if not it.retired then self.sel = it.id break end
        end
        if not self.sel and all[1] then self.sel = all[1].id end
        if not self.sel and inGuild then self.sel = "new" end
    end
    if self.sel == "new" and not inGuild then self.sel = nil end

    -- rows: active ones, then the Retired fold
    local list = {}
    if kudos then
        local given = KudosGiven()
        local active, retired = {}, {}
        for _, k in ipairs(all) do
            local item = { obj = k, countText = Plural(given[k.id] or 0, "given", "given") }
            if k.retired then retired[#retired + 1] = item else active[#active + 1] = item end
        end
        for i, item in ipairs(active) do
            item.stripe, item.first, item.last = i % 2 == 0, i == 1, i == #active
            list[#list + 1] = item
        end
        if #retired > 0 then
            list[#list + 1] = { fold = true, count = #retired }
            if self.showRetired then
                for i, item in ipairs(retired) do
                    item.stripe, item.first, item.last = i % 2 == 0, i == 1, i == #retired
                    list[#list + 1] = item
                end
            end
        end
        self.counter:SetText(("%d / %d active"):format(#active, D.MAX_KUDOS))
    else
        for i, tag in ipairs(all) do
            list[#list + 1] = { obj = tag, countText = Plural(ns.Roster:TagCount(tag.id), "member", "members"),
                stripe = i % 2 == 0, first = i == 1, last = i == #all }
        end
        self.counter:SetText(Plural(#all, "tag", "tags"))
    end
    self.rows = list
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)

    if not inGuild then
        self.emptyText:SetText(kudos and "Join a guild to manage kudos." or "Join a guild to manage tags.")
    elseif #list == 0 then
        self.emptyText:SetText(kudos and "No kudos yet." or "No tags yet.")
    else
        self.emptyText:SetText("")
    end

    if self.sel and not self.draft then self:ResetDraft() end
    self:UpdateEditor()
end

-- The row item for the selection (for its place in the list).
local function SelectedItem()
    for _, item in ipairs(TV.rows or {}) do
        if item.obj and item.obj.id == TV.sel then return item end
    end
end

function TV:UpdateEditor()
    local ed, d = self.editor, self.draft
    if not (self.sel and d) then
        ed:Hide()
        self.edEmpty:SetText(ns.DB:Guild() and "" or "Join a guild first.")
        self.edEmpty:Show()
        return
    end
    self.edEmpty:Hide()
    ed:Show()
    local kudos, it = IsKudos(), self:Selected()
    local noun = kudos and "Kudos" or "Tag"
    local icon = self:DisplayIcon()
    local r, g, b = D:TagColor(d.color)
    local text = ns.Trim(d.name)
    local fake = { name = text ~= "" and text or (noun .. " name"), color = d.color, icon = icon }

    self.iconButton.Tex:SetTexture(icon)
    self.iconButton:SetBackdropBorderColor(r, g, b, 1)
    self.title:SetText(it and fake.name or ("New " .. noun))
    self.preview:SetTag(fake, not (it and it.retired))
    self.previewIcon:SetTag(fake)
    self.previewIcon:SetShown(not kudos) -- kudos have no roster column

    -- the description box is for kudos only
    self.descLabel:SetShown(kudos)
    self.descCount:SetShown(kudos)
    self.descFrame:SetShown(kudos)
    self.iconLabel:ClearAllPoints()
    if kudos then
        self.iconLabel:SetPoint("TOPLEFT", self.descFrame, "BOTTOMLEFT", -4, -12)
        self.descCount:SetText(("%d / %d"):format(#(d.desc or ""), D.MAX_KUDOS_DESC))
    else
        self.iconLabel:SetPoint("TOPLEFT", self.nameBox, "BOTTOMLEFT", -6, -12)
    end
    self.colorButton:SetText(D:TagColorHex(d.color) .. D:ColorName(d.color) .. "|r")

    local item = SelectedItem()
    self.orderLabel:SetShown(it ~= nil)
    self.upBtn:SetShown(it ~= nil)
    self.downBtn:SetShown(it ~= nil)
    if item then
        self.upBtn:SetEnabled(not item.first)
        self.downBtn:SetEnabled(not item.last)
    end

    -- who has it / who got it
    self.rosterLink:SetShown(it ~= nil and not kudos)
    if not it then
        self.sub:SetText("")
        self.infoLabel:SetText("")
        self.info:SetText(kudos and ("Name it, pick an icon and a color, then Save. Up to %d kudos can be active."):format(D.MAX_KUDOS)
            or "Name it, pick an icon and a color, then Save. Members can then add it from their profile.")
    elseif kudos then
        local _, byMember = KudosGiven(it.id)
        local top, total = {}, 0
        for member, n in pairs(byMember) do
            top[#top + 1] = { member = member, n = n }
            total = total + n
        end
        table.sort(top, function(a, b2)
            if a.n ~= b2.n then return a.n > b2.n end
            return a.member < b2.member
        end)
        self.sub:SetText(it.retired and "|cff9d9d9dRetired|r" or (Plural(total, "given", "given") .. " in the last 90 days"))
        self.infoLabel:SetText("Top in the last 90 days")
        local lines = {}
        for i = 1, math.min(5, #top) do
            lines[i] = ns.ShortName(top[i].member) .. "  |cff9d9d9dx" .. top[i].n .. "|r"
        end
        local body = #lines > 0 and table.concat(lines, "\n") or "|cff9d9d9dNobody has received it yet.|r"
        if it.retired then
            body = body .. "\n\n|cff9d9d9dRetired: nobody can give it now. Kudos already given stay until they're 90 days old.|r"
        end
        self.info:SetText(body)
    else
        local names = {}
        for _, e in ipairs(ns.Roster.members or {}) do
            if e.tagSet and e.tagSet[it.id] then names[#names + 1] = e.short or ns.ShortName(e.full) end
        end
        table.sort(names)
        self.sub:SetText(Plural(#names, "member", "members"))
        self.infoLabel:SetText("Who has it")
        local shown, MAX = {}, 15
        for i = 1, math.min(MAX, #names) do shown[i] = names[i] end
        local body = table.concat(shown, ", ")
        if #names > MAX then body = body .. (" and %d more"):format(#names - MAX) end
        self.info:SetText(#names > 0 and body or "|cff9d9d9dNobody yet. Members add tags from their profile.|r")
    end

    local dirty = self:Dirty()
    self.saveBtn:SetEnabled(dirty)
    self.undoBtn:SetText(it and "Undo" or (CANCEL or "Cancel"))
    self.undoBtn:SetEnabled(dirty or not it)
    self.removeBtn:SetShown(it ~= nil)
    if it then
        if kudos then
            self.removeBtn:SetText(it.retired and "Bring Back" or "Retire")
        else
            self.removeBtn:SetText("Delete")
        end
    end
    self.errorText:SetText(self.err or "")
end
