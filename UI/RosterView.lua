--[[
    Nootropic Guild Manager - Roster view
    Search bar, tag quick filters, sortable and toggleable columns,
    and the member list.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local RV = {}
ns.RosterView = RV

local ROW_H = 26
local MAX_COL_W = 420
RV.LIST_WIDTH = 966 -- usable list width; follows the window size
RV.LIST_INSET = 34  -- frame width minus list width (borders + scroll bar)

-- width: default width.  min: narrowest it shrinks to.
-- hidePriority: when the window is too narrow, lower numbers are hidden first.
-- locked: never hidden.  The last visible column fills any leftover space.
local COLUMNS = {
    { key = "name",   label = "First Name",  width = 104, min = 78, locked = true },
    { key = "second", label = "Second Name", width = 92,  min = 60, hidePriority = 9 },
    { key = "level",  label = "Lvl",         width = 36,  min = 30, justify = "CENTER", hidePriority = 3 },
    { key = "class",  label = "Class",       width = 84,  min = 56, hidePriority = 2 },
    { key = "spec",   label = "Spec",        width = 110, min = 70, hidePriority = 7 },
    { key = "main",   label = "Main / Alt",  width = 126, min = 80, hidePriority = 6 },
    { key = "zone",   label = "Location",    width = 130, min = 74, hidePriority = 3.5 },
    { key = "profs",  label = "Professions", width = 150, min = 56, hidePriority = 4 },
    { key = "tags",   label = "Tags",        width = 160, min = 70, hidePriority = 8 },
    { key = "rating", label = "Rating",      width = 86,  min = 76, hidePriority = 5, officerOnly = true },
    { key = "rank",   label = "Rank",        width = 96,  min = 56, hidePriority = 1 },
    { key = "version", label = "Version",    width = 62,  min = 50, hidePriority = 0.5 },
}
local COL = {}
for _, c in ipairs(COLUMNS) do COL[c.key] = c end

-- Columns in the order the player arranged them (saved in settings.columnOrder).
-- Unknown keys are ignored and new columns are added at their default spot.
function RV:Ordered()
    local order = ns.DB:Settings().columnOrder
    if not order or #order == 0 then return COLUMNS end
    local out, used = {}, {}
    for _, key in ipairs(order) do
        local c = COL[key]
        if c and not used[key] then
            out[#out + 1] = c
            used[key] = true
        end
    end
    for i, c in ipairs(COLUMNS) do
        if not used[c.key] then
            -- insert after the column that precedes it by default
            local pos = #out + 1
            local prev = COLUMNS[i - 1]
            for j, o in ipairs(out) do if prev and o.key == prev.key then pos = j + 1 end end
            table.insert(out, pos, c)
            used[c.key] = true
        end
    end
    return out
end

function RV:SaveOrder(list)
    local keys = {}
    for i, c in ipairs(list) do keys[i] = c.key end
    ns.DB:Settings().columnOrder = keys
end

-- Moves column `key` so it sits before `beforeKey` (nil = at the end).
function RV:MoveColumn(key, beforeKey)
    if key == beforeKey then return end
    local list = {}
    for _, c in ipairs(self:Ordered()) do if c.key ~= key then list[#list + 1] = c end end
    local pos = #list + 1
    for i, c in ipairs(list) do if c.key == beforeKey then pos = i break end end
    table.insert(list, pos, COL[key])
    self:SaveOrder(list)
    self:Relayout()
end

-- Restores default order, widths and visibility.
function RV:ResetColumns()
    local s = ns.DB:Settings()
    s.columnOrder = nil
    wipe(s.columnWidths)
    wipe(s.hiddenColumns)
    s.hiddenColumns.rating = true
    s.hiddenColumns.version = true
    self:Relayout()
    self:Refresh()
end
RV.COLUMNS = COLUMNS

local STATUS_ICONS = {
    [0] = "Interface\\FriendsFrame\\StatusIcon-Online",
    [1] = "Interface\\FriendsFrame\\StatusIcon-Away",
    [2] = "Interface\\FriendsFrame\\StatusIcon-DnD",
}

RV.query = ""
RV.tagFilter = {}
RV.selected = nil
RV.layoutVersion = 0

------------------------------------------------------------------------
-- Column layout
------------------------------------------------------------------------
-- Is the column turned on in the Columns menu? (It may still be auto-hidden.)
function RV:IsColumnShown(key)
    local c = COL[key]
    if c.officerOnly and not ns.IsOfficer() then return false end
    return c.locked or not ns.DB:Settings().hiddenColumns[key]
end

-- Can this player turn the column on at all? (Rating is for officers.)
function RV:IsColumnAvailable(key)
    local c = COL[key]
    return not c.locked and not (c.officerOnly and not ns.IsOfficer())
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Fits the visible columns into LIST_WIDTH:
--   1. columns start at their saved (or default) width
--   2. if that's too wide, every column shrinks proportionally toward its minimum
--   3. if even the minimums don't fit, columns are hidden by priority (never Name)
--   4. the last visible column fills whatever space is left
function RV:ComputeLayout()
    local s = ns.DB:Settings()
    local avail = self.LIST_WIDTH
    local vis = {}
    local ordered = self:Ordered()
    for _, c in ipairs(ordered) do
        c.autoHidden = false
        c.pref = Clamp(s.columnWidths[c.key] or c.width, c.min, MAX_COL_W)
        if self:IsColumnShown(c.key) then vis[#vis + 1] = c end
    end

    while true do
        local minSum = 0
        for _, c in ipairs(vis) do minSum = minSum + c.min end
        if minSum <= avail then break end
        local victim, vi
        for i, c in ipairs(vis) do
            if not c.locked and (not victim or c.hidePriority < victim.hidePriority) then victim, vi = c, i end
        end
        if not victim then break end
        victim.autoHidden = true
        table.remove(vis, vi)
    end
    -- Bring back any hidden column that fits in the space left over.
    local minSum = 0
    for _, c in ipairs(vis) do minSum = minSum + c.min end
    local hidden = {}
    for _, c in ipairs(COLUMNS) do if c.autoHidden then hidden[#hidden + 1] = c end end
    table.sort(hidden, function(a, b) return a.hidePriority > b.hidePriority end)
    for _, c in ipairs(hidden) do
        if minSum + c.min <= avail then
            c.autoHidden = false
            minSum = minSum + c.min
        end
    end
    wipe(vis)
    for _, c in ipairs(ordered) do
        if self:IsColumnShown(c.key) and not c.autoHidden then vis[#vis + 1] = c end
    end

    -- The last column only needs its minimum; it fills whatever is left.
    local filler = vis[#vis]
    if filler then filler.pref = filler.min end

    -- Shrink columns you haven't sized yourself first, then hand-sized ones.
    for _, c in ipairs(vis) do c.w = c.pref end
    local total = 0
    for _, c in ipairs(vis) do total = total + c.w end
    local need = total - avail
    for pass = 1, 2 do
        if need <= 0 then break end
        local slack = 0
        for _, c in ipairs(vis) do
            local userSized = s.columnWidths[c.key] ~= nil
            if (pass == 1) ~= userSized then slack = slack + (c.w - c.min) end
        end
        if slack > 0 then
            local take = math.min(need, slack)
            for _, c in ipairs(vis) do
                local userSized = s.columnWidths[c.key] ~= nil
                if (pass == 1) ~= userSized then
                    c.w = c.w - math.min(c.w - c.min, math.ceil((c.w - c.min) * take / slack))
                end
            end
            need = need - take
        end
    end

    local x = 0
    for _, c in ipairs(COLUMNS) do c.shown = false end
    for i, c in ipairs(vis) do
        c.shown = true
        if i == #vis then c.w = math.max(c.min, avail - x) end
        c.x = x
        x = x + c.w
        c.last = (i == #vis)
    end
    self.layoutVersion = self.layoutVersion + 1
end

function RV:ApplyHeaderLayout()
    for _, c in ipairs(COLUMNS) do
        local h = self.headers[c.key]
        if c.shown then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", c.x, 0)
            h:SetColumnWidth(c.w)
            h:Show()
            h.Grip:SetShown(not c.last)
        else
            h:Hide()
        end
    end
end

-- Recomputes columns and redraws visible rows without re-querying.
function RV:Relayout()
    if not self.headers then return end
    self:ComputeLayout()
    self:ApplyHeaderLayout()
    if self.scrollBox and self.scrollBox.ForEachFrame then
        self.scrollBox:ForEachFrame(function(row)
            if row.entry then RV:InitRow(row, row.entry) end
        end)
    end
    self:RefreshFilterInfo()
end

function RV:SetListWidth(w)
    w = math.floor(w)
    if w == self.LIST_WIDTH then return end
    self.LIST_WIDTH = w
    if self.header then self.header:SetWidth(w) end
    self:Relayout()
end

function RV:SetColumnShown(key, shown)
    if COL[key].locked then return end
    -- false (not nil) so a column that starts hidden stays shown after a reload
    ns.DB:Settings().hiddenColumns[key] = not shown
    self:Relayout()
    self:Refresh()
end

-- Dragging a header's right edge.
function RV:StartColumnResize(c)
    local scale = self.page:GetEffectiveScale()
    local startX = GetCursorPosition() / scale
    local startW = c.w
    self.page:SetScript("OnUpdate", function()
        local x = GetCursorPosition() / scale
        local w = math.floor(Clamp(startW + (x - startX), c.min, MAX_COL_W))
        local widths = ns.DB:Settings().columnWidths
        if widths[c.key] ~= w then
            widths[c.key] = w
            RV:Relayout()
        end
    end)
end

-- Column moving: drag a header, a gold marker shows where it will land.
function RV:DropTarget()
    local scale = self.header:GetEffectiveScale()
    local x = GetCursorPosition() / scale - (self.header:GetLeft() or 0)
    local before, markerX = nil, nil
    for _, c in ipairs(self:Ordered()) do
        if c.shown then
            if x < c.x + c.w / 2 then
                before, markerX = c.key, c.x
                break
            end
            markerX = c.x + c.w
        end
    end
    return before, markerX or 0
end

function RV:StartColumnMove(c)
    self.moving = c
    local h = self.headers[c.key]
    h:SetAlpha(0.5)
    if not self.dropMarker then
        local m = self.header:CreateTexture(nil, "OVERLAY")
        m:SetColorTexture(1, 0.82, 0, 1)
        m:SetWidth(3)
        self.dropMarker = m
    end
    self.page:SetScript("OnUpdate", function()
        local _, mx = RV:DropTarget()
        RV.dropMarker:ClearAllPoints()
        RV.dropMarker:SetPoint("TOPLEFT", RV.header, "TOPLEFT", mx - 1, 2)
        RV.dropMarker:SetPoint("BOTTOMLEFT", RV.header, "BOTTOMLEFT", mx - 1, -2)
        RV.dropMarker:Show()
    end)
end

function RV:StopColumnMove()
    local c = self.moving
    self.page:SetScript("OnUpdate", nil)
    if self.dropMarker then self.dropMarker:Hide() end
    if not c then return end
    self.moving = nil
    self.headers[c.key]:SetAlpha(1)
    local before = self:DropTarget()
    self:MoveColumn(c.key, before)
    ns.PlaySound("U_CHAT_SCROLL_BUTTON")
end

function RV:StopColumnResize()
    self.page:SetScript("OnUpdate", nil)
end

function RV:ShowColumnsMenu(owner)
    local items = { { text = "Columns", isTitle = true } }
    for _, c in ipairs(COLUMNS) do
        if self:IsColumnAvailable(c.key) then
            items[#items + 1] = {
                text = c.label .. (c.autoHidden and "  |cff9d9d9d(window too narrow)|r" or ""),
                checked = function() return RV:IsColumnShown(c.key) end,
                func = function() RV:SetColumnShown(c.key, not RV:IsColumnShown(c.key)) end,
            }
        end
    end
    items[#items + 1] = { divider = true }
    items[#items + 1] = {
        text = "Show all",
        func = function()
            local hidden = ns.DB:Settings().hiddenColumns
            for _, c in ipairs(COLUMNS) do hidden[c.key] = false end
            RV:Relayout()
            RV:Refresh()
        end,
    }
    items[#items + 1] = {
        text = "Reset column order",
        func = function()
            ns.DB:Settings().columnOrder = nil
            RV:Relayout()
        end,
    }
    items[#items + 1] = {
        text = "Reset column widths",
        func = function()
            wipe(ns.DB:Settings().columnWidths)
            RV:Relayout()
        end,
    }
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = "Export roster...", func = function() ns.Export:Open() end }
    W.ShowMenu(owner, items)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function RV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    self.page, self.frame = page, frame
    page:SetScript("OnShow", function() if RV.dirty then RV:Refresh() end end)
    page:HookScript("OnHide", function() RV:ClosePanels() end)

    self:ComputeLayout()
    self:BuildToolbar(page, frame)
    self:BuildTagsPanel(page)
    self:BuildFilterPanel(page)
    self:BuildList(page, frame.Inset)
    self:ApplyHeaderLayout()

    ns:On("ROSTER_UPDATED", function() ns.Debounce("rosterview", 0.05, function() RV:Refresh() end) end)
    -- map dot colors (Options and everyone's own dot) show in the Location column
    -- (not for each position update, which names the member)
    ns:On("LOCATIONS_CHANGED", function(full)
        if full then return end
        ns.Debounce("rosterview", 0.05, function() RV:Refresh() end)
    end)
    ns:On("TAGS_CHANGED", function()
        for id in pairs(RV.tagFilter) do
            if not ns.DB:GetTag(id) then RV.tagFilter[id] = nil end
        end
        if RV.tagsPanel:IsShown() then RV:RefreshTagsPanel() end
        RV:RefreshFilterInfo()
    end)
end

------------------------------------------------------------------------
-- Toolbar: search on the left, Tags and Filter on the right, and a
-- summary line underneath (counts, active tags and filters, Clear).
-- Columns: right-click any column header.
------------------------------------------------------------------------
local function Check(parent, text)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    end
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText(text)
    cb.Label = label
    return cb
end

-- Button with an arrow at its right edge ("Tags (2)  v", "Filter  >").
local function MenuButton(parent, text, width, arrow)
    local b = W.Button(parent, text, width, 22)
    b.Arrow = b:CreateTexture(nil, "OVERLAY")
    b.Arrow:SetSize(16, 16)
    b.Arrow:SetPoint("RIGHT", -4, 0)
    b.Arrow:SetTexture(arrow == "down" and "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" or "Interface\\ChatFrame\\ChatFrameExpandArrow")
    return b
end

function RV:BuildToolbar(page, frame)
    local search = CreateFrame("EditBox", "NootropicGMSearchBox", page, "SearchBoxTemplate")
    search:SetSize(300, 20)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 78, -33)
    search:SetAutoFocus(false)
    if search.Instructions then
        search.Instructions:SetText("Search name, profession, spec, class, note...")
    end
    search:HookScript("OnTextChanged", function(eb)
        RV.query = eb:GetText() or ""
        ns.Debounce("search", 0.12, function() RV:Refresh() end)
    end)
    W.Tooltip(search, "Searching the roster",
        "Words match names, classes, specs, professions and tags. Every word must match.",
        "|cffffd100tag:|r |cffffd100prof:|r |cffffd100spec:|r |cffffd100class:|r |cffffd100name:|r |cffffd100rank:|r |cffffd100zone:|r |cffffd100note:|r limit a word to one field.",
        "|cffffd100main:markpri|r  a main and their alts    |cffffd100is:alt|r  |cffffd100is:main|r  |cffffd100is:addon|r",
        "|cffffd100rating:4|r  four stars or better   |cffffd100level>=50|r",
        "|cffffd100-raiding|r excludes, |cffffd100tag:\"world pvp\"|r matches a phrase.",
        "Right-click a column header to choose columns.")
    self.searchBox = search

    local filter = MenuButton(page, "Filter", 96, "right")
    filter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    filter:SetScript("OnClick", function() RV:TogglePanel(RV.filterPanel) end)
    W.Tooltip(filter, "Filter", "Online only, mains or alts, class, rank, and guildmates using the addon.")
    self.filterBtn = filter

    local tags = MenuButton(page, "Tags", 96, "down")
    tags:SetPoint("RIGHT", filter, "LEFT", -6, 0)
    tags:SetScript("OnClick", function() RV:TogglePanel(RV.tagsPanel) end)
    W.Tooltip(tags, "Tags", "Show only members with the tags you tick.")
    self.tagsBtn = tags

    -- summary line
    local clear = CreateFrame("Button", nil, page)
    clear:SetSize(60, 16)
    clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -63)
    clear.Text = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clear.Text:SetPoint("RIGHT", 0, 0)
    clear.Text:SetText("|TInterface\\Buttons\\UI-StopButton:12|t Clear")
    clear:SetWidth(math.ceil(clear.Text:GetStringWidth()) + 4)
    clear:SetScript("OnClick", function() RV:ClearFilters() end)
    clear:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 1, 1) end)
    clear:SetScript("OnLeave", function(self) self.Text:SetTextColor(1, 0.82, 0) end)
    self.clearBtn = clear

    local filters = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    filters:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    filters:SetJustifyH("RIGHT")
    filters:SetWordWrap(false)
    self.filterInfo = filters

    local count = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -66)
    count:SetPoint("RIGHT", filters, "LEFT", -12, 0)
    count:SetJustifyH("LEFT")
    count:SetWordWrap(false)
    self.countText = count
end

-- A small panel that opens under a toolbar button.
local function DropPanel(page, width, height)
    local p = CreateFrame("Frame", nil, page, "BackdropTemplate")
    p:SetSize(width, height)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0.06, 0.05, 0.04, 0.97)
    p:SetBackdropBorderColor(0.7, 0.6, 0.4, 1)
    p:Hide()
    return p
end

function RV:TogglePanel(p)
    local open = p:IsShown()
    self:ClosePanels()
    if not open then
        if p == self.tagsPanel then self:RefreshTagsPanel() else self:RefreshFilterPanel() end
        p:Show()
    end
end

function RV:ClosePanels()
    if self.tagsPanel then self.tagsPanel:Hide() end
    if self.filterPanel then self.filterPanel:Hide() end
end

------------------------------------------------------------------------
-- Tags menu: every tag (icon and color) in two columns, all/any, Clear
------------------------------------------------------------------------
RV.tagAny = false

function RV:BuildTagsPanel(page)
    local p = DropPanel(page, 330, 120)
    p:SetPoint("TOPRIGHT", self.tagsBtn, "BOTTOMRIGHT", 0, -4)
    p.checks = {}
    self.tagsPanel = p

    local matchLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matchLabel:SetPoint("BOTTOMLEFT", 14, 16)
    matchLabel:SetText("Match")
    local match = W.Button(p, "", 130, 20)
    match:SetPoint("LEFT", matchLabel, "RIGHT", 8, 0)
    match:SetScript("OnClick", function(btn)
        W.ShowMenu(btn, {
            { text = "Show members with", isTitle = true },
            { text = "All ticked tags", radio = true, checked = function() return not RV.tagAny end,
              func = function() RV.tagAny = false; RV:RefreshTagsPanel(); RV:Refresh() end },
            { text = "Any ticked tag", radio = true, checked = function() return RV.tagAny end,
              func = function() RV.tagAny = true; RV:RefreshTagsPanel(); RV:Refresh() end },
        })
    end)
    p.Match = match
    local clear = W.Button(p, "Clear", 70, 20)
    clear:SetPoint("BOTTOMRIGHT", -12, 12)
    clear:SetScript("OnClick", function()
        wipe(RV.tagFilter)
        RV:RefreshTagsPanel()
        RV:Refresh()
    end)
end

function RV:RefreshTagsPanel()
    local p = self.tagsPanel
    local tags = ns.DB:GetTags()
    local COL_W, ROW = 152, 22
    for i, tag in ipairs(tags) do
        local cb = p.checks[i]
        if not cb then
            cb = Check(p, "")
            cb.Icon = cb:CreateTexture(nil, "ARTWORK")
            cb.Icon:SetSize(14, 14)
            cb.Icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cb.Label:ClearAllPoints()
            cb.Label:SetPoint("LEFT", cb.Icon, "RIGHT", 4, 0)
            cb.Label:SetWidth(COL_W - 44)
            cb.Label:SetJustifyH("LEFT")
            cb.Label:SetWordWrap(false)
            cb:SetScript("OnClick", function(self)
                if self.tagId then
                    RV.tagFilter[self.tagId] = self:GetChecked() and true or nil
                    RV:Refresh()
                end
            end)
            p.checks[i] = cb
        end
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 10 + col * COL_W, -10 - row * ROW)
        cb.tagId = tag.id
        cb.Icon:SetTexture(D:TagIcon(tag))
        cb.Label:SetText(D:TagColorHex(tag.color) .. tag.name .. "|r")
        cb:SetChecked(self.tagFilter[tag.id] and true or false)
        cb:Show()
    end
    for i = #tags + 1, #p.checks do p.checks[i]:Hide() end
    local rows = math.max(1, math.ceil(#tags / 2))
    p:SetHeight(20 + rows * ROW + 40)
    p.Match:SetText(self.tagAny and "Any ticked tag" or "All ticked tags")
end

------------------------------------------------------------------------
-- Filter menu: online only, mains/alts, class, rank, addon users
-- (saved in settings.onlineOnly and settings.rosterFilter)
------------------------------------------------------------------------
function RV:Filters()
    local s = ns.DB:Settings()
    s.rosterFilter = s.rosterFilter or {}
    return s.rosterFilter
end

local KIND_LABELS = { main = "Mains only", alt = "Alts only" }

function RV:BuildFilterPanel(page)
    local p = DropPanel(page, 250, 196)
    p:SetPoint("TOPRIGHT", self.filterBtn, "BOTTOMRIGHT", 0, -4)
    self.filterPanel = p

    local online = Check(p, "Online only")
    online:SetPoint("TOPLEFT", 10, -10)
    online:SetScript("OnClick", function(self)
        ns.DB:Settings().onlineOnly = self:GetChecked() and true or false
        RV:Refresh()
    end)
    p.Online = online

    local function Picker(label, y, onClick)
        local text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", 16, y - 4)
        text:SetText(label)
        local b = W.Button(p, "", 150, 20)
        b:SetPoint("TOPLEFT", 84, y)
        b:SetScript("OnClick", onClick)
        return b
    end
    p.Kind = Picker("Show", -40, function(btn)
        local f = RV:Filters()
        local items = { { text = "Show", isTitle = true } }
        for _, k in ipairs({ { nil, "Mains and alts" }, { "main", "Mains only" }, { "alt", "Alts only" } }) do
            items[#items + 1] = { text = k[2], radio = true, checked = function() return f.kind == k[1] end,
                func = function() f.kind = k[1]; RV:RefreshFilterPanel(); RV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    p.Class = Picker("Class", -66, function(btn)
        local f = RV:Filters()
        local items = { { text = "Class", isTitle = true },
            { text = "Any", radio = true, checked = function() return f.classFile == nil end,
              func = function() f.classFile = nil; RV:RefreshFilterPanel(); RV:Refresh() end } }
        for _, cls in ipairs(D.CLASSES) do
            items[#items + 1] = { text = ("|c%s%s|r"):format(ns.ClassHex(cls), D:ClassName(cls)), radio = true,
                checked = function() return f.classFile == cls end,
                func = function() f.classFile = cls; RV:RefreshFilterPanel(); RV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    p.Rank = Picker("Rank", -92, function(btn)
        local f = RV:Filters()
        local items = { { text = "Rank", isTitle = true },
            { text = "Any", radio = true, checked = function() return f.rank == nil end,
              func = function() f.rank = nil; RV:RefreshFilterPanel(); RV:Refresh() end } }
        for _, rank in ipairs(RV:RankNames()) do
            items[#items + 1] = { text = rank, radio = true, checked = function() return f.rank == rank end,
                func = function() f.rank = rank; RV:RefreshFilterPanel(); RV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)

    local addon = Check(p, "Only guildmates using the addon")
    addon:SetPoint("TOPLEFT", 10, -118)
    addon:SetScript("OnClick", function(self)
        RV:Filters().addonOnly = self:GetChecked() and true or nil
        RV:Refresh()
    end)
    p.Addon = addon

    local reset = W.Button(p, "Reset filters", 110, 20)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    reset:SetScript("OnClick", function()
        ns.DB:Settings().onlineOnly = false
        wipe(RV:Filters())
        RV:RefreshFilterPanel()
        RV:Refresh()
    end)
    local close = W.Button(p, CLOSE or "Close", 70, 20)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() p:Hide() end)
end

-- Ranks in the guild's order (highest first), from the roster.
function RV:RankNames()
    local byIndex, out = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        if e.rank ~= "" and not byIndex[e.rankIndex] then byIndex[e.rankIndex] = e.rank end
    end
    local idx = {}
    for i in pairs(byIndex) do idx[#idx + 1] = i end
    table.sort(idx)
    for _, i in ipairs(idx) do out[#out + 1] = byIndex[i] end
    return out
end

function RV:RefreshFilterPanel()
    local p, f = self.filterPanel, self:Filters()
    p.Online:SetChecked(ns.DB:Settings().onlineOnly and true or false)
    p.Kind:SetText(KIND_LABELS[f.kind] or "Mains and alts")
    p.Class:SetText(f.classFile and ("|c%s%s|r"):format(ns.ClassHex(f.classFile), D:ClassName(f.classFile)) or "Any")
    p.Rank:SetText(f.rank or "Any")
    p.Addon:SetChecked(f.addonOnly and true or false)
end

-- Everything the Tags and Filter menus narrow the roster by, for Query.
function RV:QueryOptions()
    local f = self:Filters()
    return { onlineOnly = ns.DB:Settings().onlineOnly, tagIds = self.tagFilter, tagAny = self.tagAny,
        kind = f.kind, classFile = f.classFile, rank = f.rank, addonOnly = f.addonOnly }
end

function RV:ClearFilters()
    wipe(self.tagFilter)
    ns.DB:Settings().onlineOnly = false
    wipe(self:Filters())
    if self.tagsPanel:IsShown() then self:RefreshTagsPanel() end
    if self.filterPanel:IsShown() then self:RefreshFilterPanel() end
    self:Refresh()
end

-- Roster of guildmates running the addon (the "x using ..." link).
function RV:ShowAddonUsers()
    self:Filters().addonOnly = true
    self:SetSearch("")
    if self.filterPanel:IsShown() then self:RefreshFilterPanel() end
    self:Refresh()
end

-- Button counts and the right side of the summary line.
function RV:RefreshFilterInfo()
    if not self.filterInfo then return end
    local f = self:Filters()
    local tagParts, n = {}, 0
    for _, tag in ipairs(ns.DB:GetTags()) do
        if self.tagFilter[tag.id] then
            n = n + 1
            tagParts[#tagParts + 1] = D:TagIconString(tag, 12) .. " " .. D:TagColorHex(tag.color) .. tag.name .. "|r"
        end
    end
    local parts = {}
    if n > 0 then parts[#parts + 1] = (self.tagAny and "Any of: " or "Tags: ") .. table.concat(tagParts, ", ") end
    local filterCount = 0
    local function add(text) filterCount = filterCount + 1; parts[#parts + 1] = text end
    if ns.DB:Settings().onlineOnly then add("online only") end
    if f.kind then add(KIND_LABELS[f.kind]:lower()) end
    if f.classFile then add(("|c%s%s|r"):format(ns.ClassHex(f.classFile), D:ClassName(f.classFile))) end
    if f.rank then add(f.rank) end
    if f.addonOnly then add("using the addon") end
    self.filterInfo:SetText(table.concat(parts, "  |cff6d6d6d-|r  "))
    self.clearBtn:SetShown(#parts > 0)
    self.tagsBtn:SetText(n > 0 and ("Tags (%d)"):format(n) or "Tags")
    self.filterBtn:SetText(filterCount > 0 and ("Filter (%d)"):format(filterCount) or "Filter")
end

------------------------------------------------------------------------
-- Headers and list
------------------------------------------------------------------------
function RV:BuildList(page, inset)
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    header:SetSize(self.LIST_WIDTH, 24)
    self.header = header
    self.headers = {}
    for _, c in ipairs(COLUMNS) do
        local h = W.ColumnHeader(header, c.label, c.width, c.justify)
        h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        h:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                RV:ShowColumnsMenu(self)
                return
            end
            local s = ns.DB:Settings()
            if s.sortKey == c.key then
                s.sortAsc = not s.sortAsc
            else
                s.sortKey = c.key
                s.sortAsc = not ns.Roster.DEFAULT_DESC[c.key]
            end
            ns.PlaySound("U_CHAT_SCROLL_BUTTON")
            RV:Refresh()
        end)

        -- Drag a header sideways to move the column
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart", function() RV:StartColumnMove(c) end)
        h:SetScript("OnDragStop", function() RV:StopColumnMove() end)

        -- Resize grip on the right edge
        local grip = CreateFrame("Button", nil, h)
        grip:SetWidth(8)
        grip:SetPoint("TOPRIGHT", 4, 0)
        grip:SetPoint("BOTTOMRIGHT", 4, 0)
        grip:SetFrameLevel(h:GetFrameLevel() + 5)
        grip.Line = grip:CreateTexture(nil, "OVERLAY")
        grip.Line:SetColorTexture(1, 0.82, 0, 0.9)
        grip.Line:SetWidth(2)
        grip.Line:SetPoint("TOP", 0, -2)
        grip.Line:SetPoint("BOTTOM", 0, 2)
        grip.Line:Hide()
        grip:SetScript("OnEnter", function(self)
            self.Line:Show()
            if SetCursor then pcall(SetCursor, "UI_RESIZE_CURSOR") end
        end)
        grip:SetScript("OnLeave", function(self)
            if not RV.page:GetScript("OnUpdate") then self.Line:Hide() end
            if ResetCursor then ResetCursor() end
        end)
        grip:SetScript("OnMouseDown", function() RV:StartColumnResize(c) end)
        grip:SetScript("OnMouseUp", function(self)
            RV:StopColumnResize()
            if not self:IsMouseOver() then self.Line:Hide() end
        end)
        h.Grip = grip

        self.headers[c.key] = h
    end

    local scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, entry) RV:InitRow(row, entry) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 20)
    empty:SetWidth(420)
    self.emptyText = empty
end

------------------------------------------------------------------------
-- Rows: every column is its own cell frame, so hiding a column just hides
-- its cell and moves the others.
------------------------------------------------------------------------
local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function BuildRow(row)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetColorTexture(1, 1, 1, 0.035)

    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetAllPoints()
    row.Selected:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    row.Selected:SetBlendMode("ADD")
    row.Selected:SetVertexColor(1, 0.82, 0, 0.5)

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.45)

    local content = CreateFrame("Frame", nil, row)
    content:SetAllPoints()
    content:EnableMouse(false)
    row.Content = content

    row.cells = {}
    for _, c in ipairs(COLUMNS) do
        local cell = CreateFrame("Frame", nil, content)
        cell:SetHeight(ROW_H)
        cell:EnableMouse(false)
        row.cells[c.key] = cell
    end
    local cells = row.cells

    -- Name
    row.Status = cells.name:CreateTexture(nil, "ARTWORK")
    row.Status:SetSize(12, 12)
    row.Status:SetPoint("LEFT", 4, 0)
    row.ClassIcon = cells.name:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetSize(16, 16)
    row.ClassIcon:SetPoint("LEFT", 18, 0)
    row.Name = Text(cells.name, "GameFontNormal")
    row.Name:SetPoint("LEFT", row.ClassIcon, "RIGHT", 5, 0)
    row.Name:SetPoint("RIGHT", -4, 0)

    -- Second name
    row.Second = Text(cells.second, "GameFontNormal")
    row.Second:SetPoint("LEFT", 6, 0)
    row.Second:SetPoint("RIGHT", -4, 0)

    -- Level
    row.Level = Text(cells.level, nil, "CENTER")
    row.Level:SetAllPoints()

    -- Class
    row.Class = Text(cells.class)
    row.Class:SetPoint("LEFT", 6, 0)
    row.Class:SetPoint("RIGHT", -4, 0)

    -- Spec
    row.SpecIcon = cells.spec:CreateTexture(nil, "ARTWORK")
    row.SpecIcon:SetSize(16, 16)
    row.SpecIcon:SetPoint("LEFT", 6, 0)
    row.Spec = Text(cells.spec)
    row.Spec:SetPoint("LEFT", row.SpecIcon, "RIGHT", 4, 0)
    row.Spec:SetPoint("RIGHT", -4, 0)

    -- Main / Alt
    row.Main = Text(cells.main)
    row.Main:SetPoint("LEFT", 6, 0)
    row.Main:SetPoint("RIGHT", -4, 0)

    -- Location: zone, then their map dot (click it to open the map)
    local DOT = 12
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    row.MapBtn = CreateFrame("Button", nil, cells.zone)
    row.MapBtn:SetSize(DOT + 6, DOT + 6) -- a little bigger than the dot, easier to click
    row.MapBtn.Border = row.MapBtn:CreateTexture(nil, "ARTWORK", nil, 1)
    row.MapBtn.Border:SetTexture(CIRCLE)
    row.MapBtn.Border:SetSize(DOT, DOT)
    row.MapBtn.Border:SetPoint("CENTER")
    row.MapBtn.Dot = row.MapBtn:CreateTexture(nil, "ARTWORK", nil, 2)
    row.MapBtn.Dot:SetTexture(CIRCLE)
    row.MapBtn.Dot:SetSize(DOT * 0.72, DOT * 0.72)
    row.MapBtn.Dot:SetPoint("CENTER")
    row.MapBtn.Glow = row.MapBtn:CreateTexture(nil, "HIGHLIGHT")
    row.MapBtn.Glow:SetTexture(CIRCLE)
    row.MapBtn.Glow:SetSize(DOT + 6, DOT + 6)
    row.MapBtn.Glow:SetPoint("CENTER")
    row.MapBtn.Glow:SetVertexColor(1, 1, 1, 0.3)
    row.MapBtn.Glow:SetBlendMode("ADD")
    row.MapBtn:SetScript("OnClick", function()
        local e = row.entry
        if e then ns.Location:OpenMap(ns.Location:MapFor(e), e.full) end
    end)
    row.MapBtn:SetScript("OnEnter", function(self)
        local e = row.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Show on map")
        if e and ns.Location:Get(e.full) then
            GameTooltip:AddLine("Opens the map at " .. e.short .. "'s location.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Opens the map to " .. (e and e.zone or "their zone") .. ".", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.MapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.Zone = Text(cells.zone)
    row.Zone:SetPoint("LEFT", 6, 0)
    row.Zone:SetPoint("RIGHT", -4, 0)

    -- Professions (up to 3)
    row.Profs = {}
    for i = 1, 3 do
        local icon = cells.profs:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 6 + (i - 1) * 48, 0)
        local text = Text(cells.profs)
        text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        row.Profs[i] = { icon = icon, text = text }
    end
    row.NoProfs = Text(cells.profs, "GameFontDisableSmall")
    row.NoProfs:SetPoint("LEFT", 6, 0)
    row.NoProfs:SetText("-")

    -- Tags (icons only; the tooltip lists their names)
    row.TagIcons = {}
    row.MorePill = W.Pill(cells.tags, 16, 10)
    row.MorePill:EnableMouse(false)

    -- Rating
    row.Stars = W.Stars(cells.rating, 13, false)
    row.Stars:SetPoint("LEFT", 8, 0)

    -- Rank
    row.Rank = Text(cells.rank)
    row.Rank:SetPoint("LEFT", 6, 0)
    row.Rank:SetPoint("RIGHT", -4, 0)
    row.Rank:SetTextColor(0.8, 0.8, 0.8)

    -- Addon version
    row.Version = Text(cells.version)
    row.Version:SetPoint("LEFT", 6, 0)
    row.Version:SetPoint("RIGHT", -4, 0)

    row:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        if button == "RightButton" then
            RV:ShowRowMenu(self, e)
        else
            RV:Select(e.full)
        end
    end)
    row:SetScript("OnEnter", function(self) RV:ShowRowTooltip(self, self.entry) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function LayoutRow(row)
    for _, c in ipairs(COLUMNS) do
        local cell = row.cells[c.key]
        if c.shown then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row.Content, "LEFT", c.x, 0)
            cell:SetWidth(c.w)
            cell:Show()
        else
            cell:Hide()
        end
    end
    row.layoutVersion = RV.layoutVersion
end

local TAG_ICON = 18
local TAG_STEP = TAG_ICON + 3

local function RowTagIcon(row, i)
    local t = row.TagIcons[i]
    if not t then
        t = W.TagIcon(row.cells.tags, TAG_ICON)
        t:EnableMouse(false)
        row.TagIcons[i] = t
    end
    return t
end

local function MainLabel(e)
    if not e.isAlt then return "|cffd0d0d0Main|r" end
    local mainEntry = ns.Roster.byName[e.main]
    local hex = mainEntry and ns.ClassHex(mainEntry.classFile) or "ffbbbbbb"
    return ("|cff9d9d9dAlt of|r |c%s%s|r"):format(hex, e.mainShort)
end
RV.MainLabel = MainLabel

function RV:InitRow(row, e)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    if row.layoutVersion ~= self.layoutVersion then LayoutRow(row) end
    row.entry = e

    row.Stripe:SetShown(e._stripe)
    row.Selected:SetShown(self.selected == e.full)
    row.Content:SetAlpha(e.online and 1 or 0.55)

    -- Name
    if e.online then
        row.Status:SetTexture(STATUS_ICONS[e.status] or STATUS_ICONS[0])
        row.Status:Show()
    else
        row.Status:Hide()
    end
    W.SetClassIcon(row.ClassIcon, e.classFile)
    row.Name:SetText(e.first)
    row.Name:SetTextColor(ns.ClassColor(e.classFile))
    row.Second:SetText(e.second)
    row.Second:SetTextColor(ns.ClassColor(e.classFile))

    row.Level:SetText(e.level > 0 and e.level or "")

    row.Class:SetText(e.className)
    row.Class:SetTextColor(ns.ClassColor(e.classFile))

    local specIcon = D:SpecIcon(e.classFile, e.spec)
    if specIcon then
        W.SetIcon(row.SpecIcon, specIcon)
        row.SpecIcon:Show()
    else
        row.SpecIcon:Hide()
    end
    row.Spec:ClearAllPoints()
    row.Spec:SetPoint("LEFT", specIcon and row.SpecIcon or row.cells.spec, specIcon and "RIGHT" or "LEFT", specIcon and 4 or 6, 0)
    row.Spec:SetPoint("RIGHT", -4, 0)
    row.Spec:SetText(e.spec or "|cff6d6d6d-|r")

    row.Main:SetText(MainLabel(e))

    -- Location (the map dot only when we know which map to open), the dot
    -- right after the zone name, colored like their dot on the world map
    if COL.zone.shown then
        local zone = (e.zone ~= "" and e.zone) or nil
        row.Zone:SetText(zone or "|cff6d6d6d-|r")
        local hasMap = zone and ns.Location:MapFor(e) ~= nil
        row.MapBtn:SetShown(hasMap and true or false)
        if hasMap then
            local room = math.max(0, (COL.zone.w or 130) - 6 - 4 - 18)
            local textW = math.min(math.ceil(row.Zone:GetStringWidth()), room)
            row.Zone:SetPoint("RIGHT", -(4 + 18), 0)
            row.MapBtn:ClearAllPoints()
            row.MapBtn:SetPoint("LEFT", row.MapBtn:GetParent(), "LEFT", 6 + textW + 1, 0)
            local fr, fg, fb, br, bg, bb = ns.Location:DotColors(e.full, e.classFile)
            row.MapBtn.Dot:SetVertexColor(fr, fg, fb)
            row.MapBtn.Border:SetVertexColor(br, bg, bb, 0.9)
        else
            row.Zone:SetPoint("RIGHT", -4, 0)
        end
    end

    -- Professions
    local fit = COL.profs.shown and math.max(1, math.floor((COL.profs.w - 6) / 48)) or 0
    for i = 1, 3 do
        local slot, p = row.Profs[i], e.profs[i]
        if p and i <= fit then
            W.SetIcon(slot.icon, D:ProfIcon(p))
            slot.icon:Show()
            slot.text:SetText(p.rank and p.rank > 0 and p.rank or "")
            slot.text:Show()
        else
            slot.icon:Hide()
            slot.text:Hide()
        end
    end
    row.NoProfs:SetShown(#e.profs == 0)

    -- Tags
    if COL.tags.shown then
        local maxW = COL.tags.w - 10
        local x, shown = 0, 0
        for i, tag in ipairs(e.tagList) do
            local reserve = (i < #e.tagList) and 28 or 0
            if x + TAG_ICON + reserve > maxW then break end
            local t = RowTagIcon(row, i)
            t:SetTag(tag)
            t:ClearAllPoints()
            t:SetPoint("LEFT", row.cells.tags, "LEFT", 6 + x, 0)
            t:Show()
            x = x + TAG_STEP
            shown = i
        end
        for i = shown + 1, #row.TagIcons do row.TagIcons[i]:Hide() end
        if shown < #e.tagList then
            row.MorePill:SetLabel("+" .. (#e.tagList - shown))
            row.MorePill:ClearAllPoints()
            row.MorePill:SetPoint("LEFT", row.cells.tags, "LEFT", 6 + x, 0)
            row.MorePill:Show()
        else
            row.MorePill:Hide()
        end
    end

    row.Stars:SetValue(e.rating)
    row.Rank:SetText(e.rank)
    if row.cells.version:IsShown() then
        if not e.hasAddon then
            row.Version:SetText("|cff6d6d6d-|r")
        elseif ns.Roster:IsOutdated(e) then
            -- red: someone in the guild has a newer version
            row.Version:SetText("|cffff4040" .. (e.version or "old") .. "|r")
        else
            row.Version:SetText("|cffffffff" .. e.version .. "|r")
        end
    end
end

------------------------------------------------------------------------
-- Row interactions
------------------------------------------------------------------------
-- hint: replaces the bottom "Click for details" line (used by the map dots).
function RV:ShowRowTooltip(row, e, hint)
    if not e then return end
    local GOLD = { 1, 0.82, 0 }
    local function Pair(left, right)
        GameTooltip:AddDoubleLine(left, right, GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local PF = ns.Profile
    local pronouns = PF:Pronouns(e.full)
    GameTooltip:AddLine(e.short .. (pronouns and ("  |cffb0b0b0(" .. pronouns .. ")|r") or ""), ns.ClassColor(e.classFile))
    GameTooltip:AddLine(("Level %d %s"):format(e.level, e.className), 1, 1, 1)
    local status = PF:Status(e.full)
    if status then GameTooltip:AddLine("\"" .. status .. "\"", 1, 0.82, 0, true) end
    local hours = PF:Hours(e.full) -- local or server time, as your game clock is set
    local summary = hours and PF.Summary(hours)
    if summary then
        GameTooltip:AddLine(("Usually online: %s (%s)"):format(summary, PF.ClockLabel()), 0.7, 0.7, 0.7, true)
    end
    local kudos = PF:KudosList(e.full)
    if #kudos > 0 then
        local parts = {}
        for i = 1, math.min(3, #kudos) do parts[i] = ("%s x%d"):format(kudos[i].type.name, kudos[i].count) end
        GameTooltip:AddLine("Kudos: " .. table.concat(parts, ", "), 0.94, 0.87, 0.69, true)
    end
    if e.spec then Pair("Specialization", e.spec .. (e.dist and (" (" .. e.dist .. ")") or "")) end
    if e.isAlt then
        Pair("Alt of", e.mainShort)
    elseif #e.alts > 0 then
        local names = {}
        for i, full in ipairs(e.alts) do names[i] = ns.ShortName(full) end
        Pair("Alts", table.concat(names, ", "))
    end
    Pair("Rank", e.rank)
    if e.online then
        Pair("Zone", e.zone)
    else
        Pair("Last online", ns.FormatLastSeen(e.lastOnline) .. " ago")
    end
    for _, p in ipairs(e.profs) do
        local rank = (p.rank and p.rank > 0) and (p.max and p.max > 0 and (p.rank .. " / " .. p.max) or tostring(p.rank)) or "-"
        GameTooltip:AddDoubleLine("|T" .. D:ProfIcon(p) .. ":14:14:0:0:64:64:5:59:5:59|t " .. p.name, rank, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if #e.tagList > 0 then
        local names = {}
        for i, tag in ipairs(e.tagList) do names[i] = D:TagLabel(tag, 14) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Tags", GOLD[1], GOLD[2], GOLD[3])
        -- two per line so long lists stay readable
        for i = 1, #names, 2 do
            GameTooltip:AddLine(names[i] .. (names[i + 1] and ("     " .. names[i + 1]) or ""), 1, 1, 1)
        end
    end
    if ns.IsOfficer() then Pair("Rating", D:StarText(e.rating)) end
    if e.hasAddon then
        Pair("Addon version", e.version or "|cffff40401.10 or older|r (never reported a version)")
    end
    if e.note then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(e.note, 0.85, 0.85, 0.85, true)
    end
    if e.publicNote ~= "" then
        GameTooltip:AddLine("Guild note: " .. e.publicNote, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(hint or "Click for details, right-click for quick actions.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function RV:ShowRowMenu(row, e)
    local full = e.full
    local tagItems = {}
    for _, tag in ipairs(ns.DB:GetTags()) do
        tagItems[#tagItems + 1] = {
            text = D:TagLabel(tag, 14),
            checked = function() local m = ns.DB:GetMember(full); return m and m.tags and m.tags[tag.id] end,
            func = function() ns.DB:SetTag(full, tag.id) end,
        }
    end
    local ratingItems = {}
    for i = 5, 0, -1 do
        ratingItems[#ratingItems + 1] = {
            text = i > 0 and D:StarText(i, 12) or "Clear rating",
            radio = true,
            checked = function() local m = ns.DB:GetMember(full); return (m and m.rating or 0) == i end,
            func = function() ns.DB:SetRating(full, i) end,
        }
    end

    local altItems
    if e.isAlt then
        altItems = {
            { text = "Change main...", func = function() ns.DetailPanel:PickMainFor(full) end },
            { text = "Make " .. e.short .. " the main", func = function() ns.DB:MakeMain(full) end },
            { text = "Unlink from " .. e.mainShort, func = function() ns.DB:ClearMain(full) end },
        }
    else
        altItems = {
            { text = "Mark as alt of...", func = function() ns.DetailPanel:PickMainFor(full) end },
            { text = "Add an alt...", func = function() ns.DetailPanel:PickAltFor(full) end },
        }
    end

    local items = { { text = e.short, isTitle = true } }
    if ns.DB:CanEditTags(full) and #tagItems > 0 then items[#items + 1] = { text = "Tags", submenu = tagItems } end
    if ns.DB:CanRate() then items[#items + 1] = { text = "Rating", submenu = ratingItems } end
    if ns.DB:CanEditLinks() then items[#items + 1] = { text = "Main / Alt", submenu = altItems } end
    if ns.Profile:CanGiveKudos(full) then
        items[#items + 1] = { text = "Give Kudos", submenu = ns.DetailPanel:KudosMenuItems(e) }
    end
    for _, it in ipairs({
        { divider = true },
        { text = "Open Profile", func = function() RV:Select(full) end },
        { text = "Whisper", func = function()
            local target = ns.ChatName(full)
            if ChatFrame_SendTell then ChatFrame_SendTell(target)
            elseif ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(target) end
        end },
        { text = "Invite to Group", disabled = not e.online, func = function()
            local target = ns.ChatName(full)
            if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target)
            elseif InviteUnit then InviteUnit(target) end
        end },
    }) do items[#items + 1] = it end
    W.ShowMenu(row, items)
end

function RV:Select(full)
    self.selected = full
    self:UpdateSelection()
    ns.DetailPanel:Show(full)
end

function RV:ClearSelection()
    self.selected = nil
    self:UpdateSelection()
end

function RV:UpdateSelection()
    if not self.scrollBox or not self.scrollBox.ForEachFrame then return end
    self.scrollBox:ForEachFrame(function(row)
        if row.Selected then row.Selected:SetShown(row.entry and row.entry.full == RV.selected) end
    end)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function RV:SetSearch(text)
    if self.searchBox then self.searchBox:SetText(text or "") end
end

function RV:Refresh()
    if not self.page then return end
    if not self.page:IsVisible() then
        self.dirty = true
        return
    end
    self.dirty = false
    ns.Count("rosterRedraws")

    local s = ns.DB:Settings()
    if s.sortKey and not COL[s.sortKey] then s.sortKey = "rank" end -- from an older version
    local list = ns.Roster:Query(self.query, self:QueryOptions())
    ns.Roster:Sort(list, s.sortKey, s.sortAsc)
    for i, e in ipairs(list) do e._stripe = (i % 2 == 0) end

    local provider = CreateDataProvider(list)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(provider, retain)

    for key, h in pairs(self.headers) do
        h:SetSortState(key == s.sortKey and (s.sortAsc and "asc" or "desc") or nil)
    end

    -- summary: "9 members - 3 online - 2 using the addon - showing 4"
    local total, online, withAddon = ns.Roster:Stats()
    local SEP = "  |cff6d6d6d-|r  "
    local summary = (total == 1 and "1 member" or (total .. " members")) .. SEP
        .. ("|cff40ff40%d online|r"):format(online) .. SEP
        .. (withAddon == 1 and "1 using the addon" or (withAddon .. " using the addon"))
    if #list ~= total then summary = summary .. SEP .. ("|cffffd100showing %d|r"):format(#list) end
    self.countText:SetText(summary)

    if not IsInGuild() then
        self.emptyText:SetText("You are not in a guild.")
    elseif total == 0 then
        self.emptyText:SetText("Loading guild roster...")
    elseif #list == 0 then
        self.emptyText:SetText("No members match your search and filters.")
    else
        self.emptyText:SetText("")
    end

    self:RefreshFilterInfo()
end
