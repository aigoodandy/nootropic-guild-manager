--[[
    Nootropic Guild Manager - Column sets
    Movable, resizable, hideable list columns, shared by the Recruitment tab
    and the compact roster (the Roster tab has its own, older copy of this in
    RosterView.lua):

      - drag a header sideways to move its column (a gold marker shows where)
      - drag a header's right edge to resize it
      - right-click a header for the Columns menu: show/hide each column,
        Show all, and reset order / widths / everything
      - columns fit the list width: they shrink toward their minimum, then
        low-priority ones hide; the last column fills what's left

    local set = ns.Columns.New({
        columns = { { key, label, width, min, locked = true (always shown),
                      pinned = true (always first, can't move), fixed = true
                      (can't resize), hidePriority (lower hides first),
                      justify, padL, padR }, ... },
        store = function() return savedTable end,  -- gets order, widths, hidden
        defaultHidden = { key = true },
        onChange = function() end,                  -- redraw rows
        onSort = function(key) end,                 -- left-click a header (optional)
    })
    set:BuildHeaders(headerFrame)   set:Layout(width)   set:PlaceCells(row, cells, anchor)
]]
local _, ns = ...
local W = ns.Widgets
local CS = {}
CS.__index = CS
ns.Columns = CS

local MAX_W = 420

function CS.New(opts)
    local set = setmetatable({
        columns = opts.columns, store = opts.store, defaultHidden = opts.defaultHidden or {},
        onChange = opts.onChange, onSort = opts.onSort, version = 0, byKey = {}, avail = 400,
    }, CS)
    for _, c in ipairs(set.columns) do
        c.min = c.min or c.width
        set.byKey[c.key] = c
    end
    return set
end

function CS:Data()
    local s = self.store()
    s.widths = s.widths or {}
    s.hidden = s.hidden or {}
    return s
end

-- Turned on in the Columns menu? (It may still be hidden by a narrow window.)
function CS:IsShown(key)
    local c = self.byKey[key]
    if not c then return false end
    if c.locked then return true end
    local h = self:Data().hidden[key]
    if h == nil then return not self.defaultHidden[key] end
    return not h
end

function CS:SetShown(key, on)
    if self.byKey[key].locked then return end
    self:Data().hidden[key] = not on -- false, not nil, so a column that starts hidden stays shown
    self:Relayout()
end

-- Columns in the saved order. Pinned columns stay first; columns the saved
-- order doesn't know (new ones) go back to their default spot.
function CS:Ordered()
    local order = self:Data().order
    local out, used = {}, {}
    for _, c in ipairs(self.columns) do
        if c.pinned then out[#out + 1] = c; used[c.key] = true end
    end
    for _, key in ipairs(order or {}) do
        local c = self.byKey[key]
        if c and not used[key] then out[#out + 1] = c; used[key] = true end
    end
    for i, c in ipairs(self.columns) do
        if not used[c.key] then
            local pos, prev = #out + 1, self.columns[i - 1]
            for j, o in ipairs(out) do if prev and o.key == prev.key then pos = j + 1 end end
            table.insert(out, pos, c)
            used[c.key] = true
        end
    end
    return out
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
function CS:Layout(avail)
    if avail then self.avail = math.floor(avail) end
    avail = self.avail
    local widths = self:Data().widths
    local vis = {}
    for _, c in ipairs(self:Ordered()) do
        c.autoHidden = false
        c.pref = c.fixed and c.width or math.max(c.min, math.min(MAX_W, widths[c.key] or c.width))
        if self:IsShown(c.key) then vis[#vis + 1] = c end
    end

    -- too narrow even at minimum widths: hide by priority (never locked ones)
    local function MinSum()
        local n = 0
        for _, c in ipairs(vis) do n = n + (c.fixed and c.width or c.min) end
        return n
    end
    while MinSum() > avail do
        local victim, vi
        for i, c in ipairs(vis) do
            if not c.locked and (not victim or (c.hidePriority or 0) < (victim.hidePriority or 0)) then victim, vi = c, i end
        end
        if not victim then break end
        victim.autoHidden = true
        table.remove(vis, vi)
    end

    -- the last resizable column fills the leftover space; the others keep
    -- their width, shrinking toward their minimum when there isn't room
    local filler
    for i = #vis, 1, -1 do if not vis[i].fixed then filler = vis[i] break end end
    local total = 0
    for _, c in ipairs(vis) do
        c.w = (c == filler) and c.min or c.pref
        total = total + c.w
    end
    local need = total - avail
    if need > 0 then
        local slack = 0
        for _, c in ipairs(vis) do if not c.fixed and c ~= filler then slack = slack + (c.w - c.min) end end
        if slack > 0 then
            local take = math.min(need, slack)
            for _, c in ipairs(vis) do
                if not c.fixed and c ~= filler then c.w = c.w - math.ceil((c.w - c.min) * take / slack) end
            end
        end
    end
    local others = 0
    for _, c in ipairs(vis) do if c ~= filler then others = others + c.w end end
    if filler then filler.w = math.max(filler.min, avail - others) end

    for _, c in ipairs(self.columns) do c.shown, c.last = false, false end
    local x = 0
    for _, c in ipairs(vis) do
        c.shown, c.x = true, x
        x = x + c.w
    end
    if vis[#vis] then vis[#vis].last = true end
    self.version = self.version + 1
    self:ApplyHeaders()
end

function CS:Relayout()
    self:Layout()
    if self.onChange then self.onChange() end
end

-- Positions a row's cells (key -> frame or font string) when the layout changed.
function CS:PlaceCells(row, cells, anchor)
    if row._colVersion == self.version then return false end
    for _, c in ipairs(self.columns) do
        local cell = cells[c.key]
        if cell then
            if c.shown then
                local l, r = c.padL or 0, c.padR or 0
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", anchor, "LEFT", c.x + l, 0)
                cell:SetWidth(math.max(1, c.w - l - r))
                cell:Show()
            else
                cell:Hide()
            end
        end
    end
    row._colVersion = self.version
    return true
end

------------------------------------------------------------------------
-- Headers: click to sort, right-click for the menu, drag to move, edge to resize
------------------------------------------------------------------------
function CS:BuildHeaders(headerFrame)
    self.header = headerFrame
    self.headers = {}
    for _, c in ipairs(self.columns) do
        local set = self
        local h = W.ColumnHeader(headerFrame, c.label, c.width, c.justify)
        h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        h:SetScript("OnClick", function(btn, button)
            if button == "RightButton" then
                set:Menu(btn)
            elseif set.onSort then
                set.onSort(c.key)
            end
        end)
        if not c.pinned then
            h:RegisterForDrag("LeftButton")
            h:SetScript("OnDragStart", function() set:StartMove(c) end)
            h:SetScript("OnDragStop", function() set:StopMove() end)
        end
        if not c.fixed then
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
                if not set.resizing then self.Line:Hide() end
                if ResetCursor then ResetCursor() end
            end)
            grip:SetScript("OnMouseDown", function() set:StartResize(c) end)
            grip:SetScript("OnMouseUp", function(self)
                set:StopDrag()
                if not self:IsMouseOver() then self.Line:Hide() end
            end)
            h.Grip = grip
        end
        self.headers[c.key] = h
    end
end

function CS:ApplyHeaders()
    if not self.headers then return end
    for _, c in ipairs(self.columns) do
        local h = self.headers[c.key]
        if c.shown then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", c.x, 0)
            h:SetColumnWidth(c.w)
            h:Show()
            if h.Grip then h.Grip:SetShown(not c.last) end
        else
            h:Hide()
        end
    end
end

function CS:SetSortState(key, asc)
    if not self.headers then return end
    for k, h in pairs(self.headers) do
        h:SetSortState(k == key and (asc and "asc" or "desc") or nil)
    end
end

-- Dragging a header's right edge.
function CS:StartResize(c)
    local scale = self.header:GetEffectiveScale()
    local startX = GetCursorPosition() / scale
    local startW = c.w
    self.resizing = true
    self.header:SetScript("OnUpdate", function()
        local x = GetCursorPosition() / scale
        local w = math.floor(math.max(c.min, math.min(MAX_W, startW + (x - startX))))
        local widths = self:Data().widths
        if widths[c.key] ~= w then
            widths[c.key] = w
            self:Relayout()
        end
    end)
end

function CS:StopDrag()
    self.resizing = false
    self.header:SetScript("OnUpdate", nil)
end

-- Where a dragged column would land: the column it goes before, and the marker's x.
function CS:DropTarget()
    local scale = self.header:GetEffectiveScale()
    local x = GetCursorPosition() / scale - (self.header:GetLeft() or 0)
    local before, markerX
    for _, c in ipairs(self:Ordered()) do
        if c.shown and not c.pinned then
            if x < c.x + c.w / 2 then
                before, markerX = c.key, c.x
                break
            end
            markerX = c.x + c.w
        end
    end
    return before, markerX or 0
end

function CS:StartMove(c)
    self.moving = c
    self.headers[c.key]:SetAlpha(0.5)
    if not self.dropMarker then
        local m = self.header:CreateTexture(nil, "OVERLAY")
        m:SetColorTexture(1, 0.82, 0, 1)
        m:SetWidth(3)
        self.dropMarker = m
    end
    self.header:SetScript("OnUpdate", function()
        local _, mx = self:DropTarget()
        self.dropMarker:ClearAllPoints()
        self.dropMarker:SetPoint("TOPLEFT", self.header, "TOPLEFT", mx - 1, 2)
        self.dropMarker:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", mx - 1, -2)
        self.dropMarker:Show()
    end)
end

function CS:StopMove()
    local c = self.moving
    self.header:SetScript("OnUpdate", nil)
    if self.dropMarker then self.dropMarker:Hide() end
    if not c then return end
    self.moving = nil
    self.headers[c.key]:SetAlpha(1)
    self:MoveColumn(c.key, (self:DropTarget()))
    ns.PlaySound("U_CHAT_SCROLL_BUTTON")
end

-- Moves column `key` before `beforeKey` (nil = to the end) and saves the order.
function CS:MoveColumn(key, beforeKey)
    if key == beforeKey then return end
    local list = {}
    for _, c in ipairs(self:Ordered()) do if c.key ~= key then list[#list + 1] = c end end
    local pos = #list + 1
    for i, c in ipairs(list) do if c.key == beforeKey then pos = i break end end
    table.insert(list, pos, self.byKey[key])
    local keys = {}
    for i, c in ipairs(list) do keys[i] = c.key end
    self:Data().order = keys
    self:Relayout()
end

------------------------------------------------------------------------
-- Columns menu (right-click a header)
------------------------------------------------------------------------
function CS:Menu(owner)
    local items = { { text = "Columns", isTitle = true } }
    for _, c in ipairs(self:Ordered()) do
        if not c.locked then
            items[#items + 1] = {
                text = c.label .. (c.autoHidden and "  |cff9d9d9d(window too narrow)|r" or ""),
                checked = function() return self:IsShown(c.key) end,
                func = function() self:SetShown(c.key, not self:IsShown(c.key)) end,
            }
        end
    end
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = "Show all", func = function()
        local hidden = self:Data().hidden
        for _, c in ipairs(self.columns) do hidden[c.key] = false end
        self:Relayout()
    end }
    items[#items + 1] = { text = "Reset column order", func = function()
        self:Data().order = nil
        self:Relayout()
    end }
    items[#items + 1] = { text = "Reset column widths", func = function()
        wipe(self:Data().widths)
        self:Relayout()
    end }
    items[#items + 1] = { text = "Reset all columns", func = function() self:Reset() end }
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = "|cff9d9d9dDrag a header to move it, or its edge to resize.|r", disabled = true }
    W.ShowMenu(owner, items)
end

-- Default order, widths and shown columns.
function CS:Reset()
    local s = self:Data()
    s.order = nil
    wipe(s.widths)
    wipe(s.hidden)
    self:Relayout()
end
