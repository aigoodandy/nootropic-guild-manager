--[[
    Nootropic Guild Manager - Compact roster
    A small guild roster window without tabs, opened with the Compact button
    on the Roster tab. Shows First Name and Location by default. Columns move,
    resize and hide like on the Roster tab (UI/Columns.lua): drag a header,
    drag its edge, or right-click it to add Level, Class, Second Name, Spec,
    Main / Alt or Rank. Search, Online only, sorting, the roster tooltip and
    right-click menu all work as on the Roster tab. Click a name to open their
    profile in the full window; the expand arrow goes back to it.

    Saved in settings.compact = { cols = { order, widths, hidden }, onlineOnly,
    sortKey, sortAsc, pos, size }
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local CR = {}
ns.CompactRoster = CR

local ROW_H = 20
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 200, 800, 1000

-- Name is always shown; it leaves room on the left for the class icon.
local COLUMNS = {
    { key = "name",   label = "Name",        width = 96,  min = 70, locked = true, padL = 22, padR = 4 },
    { key = "second", label = "Second Name", width = 80,  min = 56, hidePriority = 5, padL = 4, padR = 4 },
    { key = "level",  label = "Lvl",         width = 30,  min = 26, justify = "CENTER", hidePriority = 2 },
    { key = "class",  label = "Class",       width = 70,  min = 50, hidePriority = 3, padL = 4, padR = 4 },
    { key = "spec",   label = "Spec",        width = 70,  min = 50, hidePriority = 4, padL = 4, padR = 4 },
    { key = "zone",   label = "Location",    width = 110, min = 70, hidePriority = 7, padL = 4, padR = 4 },
    { key = "main",   label = "Main / Alt",  width = 90,  min = 60, hidePriority = 6, padL = 4, padR = 4 },
    { key = "rank",   label = "Rank",        width = 70,  min = 50, hidePriority = 1, padL = 4, padR = 4 },
}

function CR:Settings()
    local s = ns.DB:Settings()
    s.compact = s.compact or {}
    local c = s.compact
    c.cols = c.cols or {}
    c.sortKey = c.sortKey or "name"
    if c.sortAsc == nil then c.sortAsc = true end
    c.size = c.size or { w = 280, h = 420 }
    return c
end

CR.cols = ns.Columns.New({
    columns = COLUMNS,
    store = function() return CR:Settings().cols end,
    defaultHidden = { second = true, level = true, class = true, spec = true, main = true, rank = true },
    onChange = function() CR:RedrawRows() end,
    onSort = function(key)
        local s = CR:Settings()
        if s.sortKey == key then
            s.sortAsc = not s.sortAsc
        else
            s.sortKey, s.sortAsc = key, not ns.Roster.DEFAULT_DESC[key]
        end
        ns.PlaySound("U_CHAT_SCROLL_BUTTON")
        CR:Refresh()
    end,
})

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function CR:Build()
    if self.frame then return self.frame end
    local c = self:Settings()
    local f = CreateFrame("Frame", "NootropicGMCompactRoster", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(math.max(MIN_W, math.min(MAX_W, c.size.w)), math.max(MIN_H, math.min(MAX_H, c.size.h)))
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CR:SavePosition()
    end)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f
    W.SetTitle(f, "Guild Roster")

    -- expand arrow beside the close button
    local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
    local size = close and math.floor(close:GetHeight() + 0.5) or 22
    if size < 16 then size = 22 end
    local expand = W.SizeButton(f, "expand", size, function() CR:Expand() end,
        "Expand", "Back to the full guild roster.")
    if close then
        expand:SetPoint("RIGHT", close, "LEFT", 0, 0)
    else
        expand:SetPoint("TOPRIGHT", -26, -2)
    end
    expand:MatchLevel(close)

    -- search and Online only
    local search = CreateFrame("EditBox", "NootropicGMCompactSearch", f, "SearchBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", 16, -30)
    search:SetPoint("RIGHT", f, "RIGHT", -86, 0)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText("Search") end
    search:HookScript("OnTextChanged", function() ns.Debounce("compactsearch", 0.12, function() CR:Refresh() end) end)
    W.Tooltip(search, "Search", function()
        return ("Same searches as the %s tab: names, classes, specs, professions, tags, tag:raiding, zone:barrens..."):format(ns.TabName("roster"))
    end)
    self.search = search

    local online = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    online:SetSize(22, 22)
    online:SetPoint("LEFT", search, "RIGHT", 6, 0)
    local label = online.Text or online.text
    if not label then
        label = online:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", online, "RIGHT", 1, 1)
    end
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText("Online")
    online:SetScript("OnClick", function(self)
        CR:Settings().onlineOnly = self:GetChecked() and true or false
        CR:Refresh()
    end)
    self.onlineCheck = online

    -- column headers
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 10, -56)
    header:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    header:SetHeight(24)
    self.header = header
    -- click to sort, right-click for columns, drag to move, edge to resize
    self.cols:BuildHeaders(header)

    -- list
    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 28)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, e) CR:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.emptyText:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    self.emptyText:SetWidth(180)

    -- footer: count (columns: right-click a header)
    self.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.count:SetPoint("BOTTOMLEFT", 14, 9)

    -- resize grip
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
        CR:SavePosition()
        CR:Settings().size = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
    end)
    f:SetScript("OnSizeChanged", function() CR:Layout() end)

    f:SetScript("OnShow", function()
        ns.Roster:Request()
        CR:Layout()
        CR:Refresh()
    end)
    ns:On("ROSTER_UPDATED", function()
        if f:IsShown() then ns.Debounce("compactroster", 0.1, function() CR:Refresh() end) end
    end)
    return f
end

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------
function CR:Layout()
    if not self.header then return end
    local avail = math.floor(self.header:GetWidth())
    if avail < 50 then avail = math.floor((self.frame:GetWidth() or 280) - 38) end
    self.cols:Layout(avail)
    self:RedrawRows()
end

function CR:RedrawRows()
    if self.scrollBox and self.scrollBox.ForEachFrame then
        self.scrollBox:ForEachFrame(function(row) if row.entry then CR:InitRow(row, row.entry) end end)
    end
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function BuildRow(row)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetColorTexture(1, 1, 1, 0.035)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.45)
    row.Content = CreateFrame("Frame", nil, row)
    row.Content:SetAllPoints()
    row.Content:EnableMouse(false)

    row.ClassIcon = row.Content:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetSize(14, 14)
    row.cells = {}
    for _, col in ipairs(COLUMNS) do
        local fs = row.Content:CreateFontString(nil, "OVERLAY", col.key == "name" and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetJustifyH(col.justify or "LEFT")
        fs:SetWordWrap(false)
        row.cells[col.key] = fs
    end

    row:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        if button == "RightButton" then
            ns.RosterView:ShowRowMenu(self, e)
        else
            CR:OpenProfile(e.full)
        end
    end)
    row:SetScript("OnEnter", function(self)
        ns.RosterView:ShowRowTooltip(self, self.entry, "Click to open their profile, right-click for quick actions.")
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function CR:InitRow(row, e)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    if self.cols:PlaceCells(row, row.cells, row.Content) then
        -- the class icon sits at the start of the Name column, wherever it moved
        row.ClassIcon:ClearAllPoints()
        row.ClassIcon:SetPoint("LEFT", row.Content, "LEFT", self.cols.byKey.name.x + 4, 0)
    end
    row.entry = e
    row.Stripe:SetShown(e._cstripe)
    row.Content:SetAlpha(e.online and 1 or 0.55)
    W.SetClassIcon(row.ClassIcon, e.classFile)
    local r, g, b = ns.ClassColor(e.classFile)
    local cells = row.cells
    cells.name:SetText(e.first)
    cells.name:SetTextColor(r, g, b)
    cells.second:SetText(e.second)
    cells.second:SetTextColor(r, g, b)
    cells.level:SetText(e.level > 0 and e.level or "")
    cells.class:SetText(e.className)
    cells.class:SetTextColor(r, g, b)
    cells.spec:SetText(e.spec or "|cff6d6d6d-|r")
    cells.zone:SetText(e.zone ~= "" and e.zone or "|cff6d6d6d-|r")
    cells.main:SetText(ns.RosterView.MainLabel(e))
    cells.rank:SetText(e.rank)
    cells.rank:SetTextColor(0.8, 0.8, 0.8)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function CR:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local s = self:Settings()
    self.onlineCheck:SetChecked(s.onlineOnly and true or false)
    local list = ns.Roster:Query(self.search:GetText() or "", { onlineOnly = s.onlineOnly })
    ns.Roster:Sort(list, s.sortKey, s.sortAsc)
    for i, e in ipairs(list) do e._cstripe = (i % 2 == 0) end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    self.cols:SetSortState(s.sortKey, s.sortAsc)
    local total, online = ns.Roster:Stats()
    self.count:SetText(("%d shown  -  |cff40ff40%d online|r"):format(#list, online))
    if not IsInGuild() then
        self.emptyText:SetText("You are not in a guild.")
    elseif total == 0 then
        self.emptyText:SetText("Loading guild roster...")
    elseif #list == 0 then
        self.emptyText:SetText(s.onlineOnly and "Nobody matching is online." or "No members match.")
    else
        self.emptyText:SetText("")
    end
end

------------------------------------------------------------------------
-- Position and switching
------------------------------------------------------------------------
function CR:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    self:Settings().pos = { point = point, relPoint = relPoint, x = x, y = y }
end

function CR:RestorePosition()
    local f, pos = self.frame, self:Settings().pos
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -120, 60)
    end
end

function CR:Show()
    local f = self:Build()
    if not f:IsShown() then self:RestorePosition() end
    f:Show()
end

function CR:Hide()
    if self.frame then self.frame:Hide() end
end

function CR:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

-- From the Roster tab: close the big window, show the compact roster.
function CR:Compact()
    self:Show()
    ns.UI:Hide()
end

-- Back to the full Roster tab.
function CR:Expand()
    self:Hide()
    ns.UI:OpenTab(ns.UI.TAB_ROSTER)
end

function CR:OpenProfile(full)
    self:Expand()
    ns.RosterView:Select(full)
end
