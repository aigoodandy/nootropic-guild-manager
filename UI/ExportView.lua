--[[
    Nootropic Guild Manager - Roster export
    Addons can't write files, so the roster is written out as text to copy
    (Ctrl+C) and paste into a spreadsheet or a .csv file.

      Members     the ones shown on the Roster tab (search, tags, filters) or
                  the whole guild, in the roster's sort order
      Columns     the Roster tab's visible columns, in your order, or every field
      Separator   tab (pastes into spreadsheet columns), comma (.csv) or semicolon
      Part size   big exports are split into parts of this many members; the
                  column headings are only on part 1, so pasting the parts one
                  after another makes one table. Only the shown part is built.

    Officer-only fields (rating, officer note) are only exported for officers;
    your private notes only when you tick the box.

    Saved in settings.export = { members, columns, sep, partSize, notes }
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local EX = {}
ns.Export = EX

EX.DEFAULT_PART, EX.MIN_PART, EX.MAX_PART = 250, 10, 5000

local SEPARATORS = {
    { key = "tab",       label = "Tab (spreadsheets)", char = "\t" },
    { key = "comma",     label = "Comma (.csv file)",  char = "," },
    { key = "semicolon", label = "Semicolon",          char = ";" },
}

------------------------------------------------------------------------
-- Fields
------------------------------------------------------------------------
local function Profs(e)
    local parts = {}
    for _, p in ipairs(e.profs) do
        parts[#parts + 1] = (p.rank and p.rank > 0) and (p.name .. " " .. p.rank) or p.name
    end
    return table.concat(parts, "; ")
end

local function Tags(e)
    local names = {}
    for i, tag in ipairs(e.tagList) do names[i] = tag.name end
    return table.concat(names, "; ")
end

local function Alts(e)
    local names = {}
    for i, full in ipairs(e.alts) do names[i] = ns.ShortName(full) end
    return table.concat(names, "; ")
end

-- key, heading, value(e). officer: officers only. private: only with "my notes".
-- column: the Roster tab column it stands for (visible-columns mode).
local FIELDS = {
    { key = "first",   label = "First Name",  column = "name",    get = function(e) return e.first end },
    { key = "second",  label = "Second Name", column = "second",  get = function(e) return e.second end },
    { key = "level",   label = "Level",       column = "level",   get = function(e) return e.level > 0 and tostring(e.level) or "" end },
    { key = "class",   label = "Class",       column = "class",   get = function(e) return e.className end },
    { key = "spec",    label = "Spec",        column = "spec",    get = function(e) return e.spec or "" end },
    { key = "main",    label = "Main / Alt",  column = "main",    get = function(e) return e.isAlt and ("Alt of " .. (e.mainShort or "?")) or "Main" end },
    { key = "alts",    label = "Alts",                            get = Alts },
    { key = "zone",    label = "Location",    column = "zone",    get = function(e) return e.zone end },
    { key = "online",  label = "Last Online",                     get = function(e)
        return e.online and "Online" or (ns.FormatLastSeen(e.lastOnline) .. " ago") end },
    { key = "profs",   label = "Professions", column = "profs",   get = Profs },
    { key = "tags",    label = "Tags",        column = "tags",    get = Tags },
    { key = "rating",  label = "Rating",      column = "rating",  officer = true, get = function(e) return e.rating > 0 and tostring(e.rating) or "" end },
    { key = "rank",    label = "Rank",        column = "rank",    get = function(e) return e.rank end },
    { key = "version", label = "Addon Version", column = "version", get = function(e)
        if not e.hasAddon then return "" end
        return e.version or "1.10 or older" end },
    { key = "pnote",   label = "Public Note",                     get = function(e) return e.publicNote end },
    { key = "onote",   label = "Officer Note", officer = true,    get = function(e) return e.officerNote end },
    { key = "mynote",  label = "My Note",      private = true,    get = function(e) return e.note or "" end },
}

function EX:Settings()
    local s = ns.DB:Settings()
    s.export = s.export or {}
    local x = s.export
    x.members = x.members or "shown"
    x.columns = x.columns or "visible"
    x.sep = x.sep or "tab"
    x.partSize = math.max(self.MIN_PART, math.min(self.MAX_PART, tonumber(x.partSize) or self.DEFAULT_PART))
    return x
end

-- The fields to export, in order.
function EX:Fields()
    local x = self:Settings()
    local officer = ns.IsOfficer()
    local out = {}
    local function allowed(f)
        if f.officer and not officer then return false end
        if f.private and not x.notes then return false end
        return true
    end
    if x.columns == "visible" then
        local RV = ns.RosterView
        for _, c in ipairs(RV:Ordered()) do
            if RV:IsColumnShown(c.key) then
                for _, f in ipairs(FIELDS) do
                    if f.column == c.key and allowed(f) then out[#out + 1] = f end
                end
            end
        end
        -- your own notes go on the end when ticked
        for _, f in ipairs(FIELDS) do if f.private and allowed(f) then out[#out + 1] = f end end
    else
        for _, f in ipairs(FIELDS) do if allowed(f) then out[#out + 1] = f end end
    end
    return out
end

-- The members to export, in the roster's current sort order.
function EX:Members()
    local x = self:Settings()
    local RV, R = ns.RosterView, ns.Roster
    local list
    if x.members == "shown" then
        list = R:Query(RV.query or "", RV:QueryOptions())
    else
        list = {}
        for i, e in ipairs(R.members) do list[i] = e end
    end
    local s = ns.DB:Settings()
    R:Sort(list, s.sortKey or "rank", s.sortAsc ~= false)
    return list
end

local function SepChar()
    local key = EX:Settings().sep
    for _, s in ipairs(SEPARATORS) do if s.key == key then return s.char end end
    return "\t"
end

-- One value, safe for the separator: colors removed, line breaks flattened,
-- quoted when it holds the separator or a quote.
local function Cell(v, sep)
    v = tostring(v or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    v = v:gsub("[\r\n\t]+", " ")
    if v:find(sep, 1, true) or v:find('"', 1, true) then
        v = '"' .. v:gsub('"', '""') .. '"'
    end
    return v
end

-- The text of part `n` (column headings only on part 1).
function EX:BuildPart(n)
    local members, fields = self.members, self.fields
    local size = self:Settings().partSize
    local sep = SepChar()
    local first = (n - 1) * size + 1
    local last = math.min(#members, n * size)
    local lines = {}
    if n == 1 then
        local head = {}
        for i, f in ipairs(fields) do head[i] = Cell(f.label, sep) end
        lines[1] = table.concat(head, sep)
    end
    for i = first, last do
        local e = members[i]
        local row = {}
        for j, f in ipairs(fields) do row[j] = Cell(f.get(e), sep) end
        lines[#lines + 1] = table.concat(row, sep)
    end
    return table.concat(lines, "\n"), first, last
end

function EX:PartCount()
    return math.max(1, math.ceil(#self.members / self:Settings().partSize))
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function Picker(parent, label, x, y, width, options, key)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", x, y - 4)
    text:SetText(label)
    local b = W.Button(parent, "", width, 22)
    b:SetPoint("LEFT", text, "RIGHT", 8, 0)
    b:SetScript("OnClick", function(self)
        local items = { { text = label, isTitle = true } }
        for _, o in ipairs(options) do
            items[#items + 1] = {
                text = o.label, radio = true,
                checked = function() return EX:Settings()[key] == o.key end,
                func = function()
                    EX:Settings()[key] = o.key
                    EX:Rebuild()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    b.options, b.key = options, key
    return b
end

function EX:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "NootropicGMExport", UIParent, "BackdropTemplate")
    f:SetSize(680, 470)
    f:SetFrameStrata("DIALOG")
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
    title:SetText("Export Roster")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- choices
    self.membersBtn = Picker(f, "Members", 22, -42, 150, {
        { key = "shown", label = "Shown on the roster" },
        { key = "all",   label = "Whole guild" },
    }, "members")
    self.columnsBtn = Picker(f, "Columns", 248, -42, 150, {
        { key = "visible", label = "Visible columns" },
        { key = "all",     label = "Every field" },
    }, "columns")
    self.sepBtn = Picker(f, "Separator", 470, -42, 140, SEPARATORS, "sep")

    local partLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    partLabel:SetPoint("TOPLEFT", 22, -74)
    partLabel:SetText("Part size")
    local part = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    part:SetSize(50, 20)
    part:SetPoint("LEFT", partLabel, "RIGHT", 12, 0)
    part:SetAutoFocus(false)
    part:SetNumeric(true)
    part:SetMaxLetters(4)
    local function applyPart()
        local n = tonumber(part:GetText())
        if n then EX:Settings().partSize = n end
        part:SetText(tostring(EX:Settings().partSize))
        part:ClearFocus()
        EX:Rebuild()
    end
    part:SetScript("OnEnterPressed", applyPart)
    part:SetScript("OnEditFocusLost", applyPart)
    part:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    W.Tooltip(part, "Part size", ("Members per part, %d to %d. Big exports are split into parts so the text box stays quick; copy and paste them one after another."):format(EX.MIN_PART, EX.MAX_PART),
        "Press Enter to apply.")
    self.partBox = part
    local partHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    partHint:SetPoint("LEFT", part, "RIGHT", 8, 0)
    partHint:SetText("members per part")

    local notes = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    notes:SetSize(22, 22)
    notes:SetPoint("TOPLEFT", 334, -71)
    local nl = notes.Text or notes.text
    if not nl then
        nl = notes:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nl:SetPoint("LEFT", notes, "RIGHT", 2, 1)
    end
    nl:SetFontObject("GameFontHighlightSmall")
    nl:SetText("Include my private notes")
    notes:SetScript("OnClick", function(self)
        EX:Settings().notes = self:GetChecked() and true or nil
        EX:Rebuild()
    end)
    self.notesCheck = notes

    -- the text
    local ef, box = W.ScrollEditor(f)
    ef:SetPoint("TOPLEFT", 24, -104)
    ef:SetPoint("BOTTOMRIGHT", -40, 76)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetMaxLetters(0)
    -- it's for copying: typing doesn't change the export
    box:HookScript("OnTextChanged", function(self, user)
        if user and EX.text then self:SetText(EX.text); self:HighlightText() end
    end)
    self.box = box

    -- part navigation and info
    self.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.info:SetPoint("BOTTOMLEFT", 24, 50)
    self.info:SetPoint("RIGHT", -24, 0)
    self.info:SetJustifyH("LEFT")

    local prev = W.Button(f, "< Previous", 100, 22)
    prev:SetPoint("BOTTOMLEFT", 22, 18)
    prev:SetScript("OnClick", function() EX:ShowPart(EX.part - 1) end)
    self.prevBtn = prev
    local nextBtn = W.Button(f, "Next >", 100, 22)
    nextBtn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    nextBtn:SetScript("OnClick", function() EX:ShowPart(EX.part + 1) end)
    self.nextBtn = nextBtn
    local selectBtn = W.Button(f, "Select All", 100, 22)
    selectBtn:SetPoint("LEFT", nextBtn, "RIGHT", 18, 0)
    selectBtn:SetScript("OnClick", function() EX:SelectAll() end)
    W.Tooltip(selectBtn, "Select all", "Then press Ctrl+C to copy.")
    local done = W.Button(f, CLOSE or "Close", 90, 22)
    done:SetPoint("BOTTOMRIGHT", -22, 18)
    done:SetScript("OnClick", function() f:Hide() end)
    return f
end

function EX:SelectAll()
    self.box:SetFocus()
    self.box:HighlightText()
end

-- Rebuilds the member list and fields (after a choice changed) and shows part 1.
function EX:Rebuild()
    if not self.frame then return end
    local x = self:Settings()
    self.members = self:Members()
    self.fields = self:Fields()
    for _, b in ipairs({ self.membersBtn, self.columnsBtn, self.sepBtn }) do
        for _, o in ipairs(b.options) do if o.key == x[b.key] then b:SetText(o.label) end end
    end
    if not self.partBox:HasFocus() then self.partBox:SetText(tostring(x.partSize)) end
    self.notesCheck:SetChecked(x.notes and true or false)
    self:ShowPart(1)
end

function EX:ShowPart(n)
    local parts = self:PartCount()
    n = math.max(1, math.min(parts, n or 1))
    self.part = n
    local text, first, last = self:BuildPart(n)
    self.text = text
    self.box:SetText(text)
    self.box:SetCursorPosition(0)
    self.prevBtn:SetEnabled(n > 1)
    self.nextBtn:SetEnabled(n < parts)
    local total = #self.members
    local where
    if total == 0 then
        where = "|cffff8080No members to export.|r Check the roster's search and filters, or choose Whole guild."
    elseif parts == 1 then
        where = ("%d member%s, %d column%s - all selected, press |cffffffffCtrl+C|r to copy."):format(
            total, total == 1 and "" or "s", #self.fields, #self.fields == 1 and "" or "s")
    else
        where = ("%d members, %d columns - |cffffd100part %d of %d|r (members %d-%d) selected, press |cffffffffCtrl+C|r to copy, then Next.%s"):format(
            total, #self.fields, n, parts, first, last, n == 1 and "" or "  |cff9d9d9dNo headings on this part.|r")
    end
    self.info:SetText(where)
    self:SelectAll()
end

function EX:Open()
    local f = self:Build()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:Show()
    f:Raise()
    self:Rebuild()
end
