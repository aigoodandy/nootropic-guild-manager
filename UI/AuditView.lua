--[[
    Nootropic Guild Manager - Audit tab (officers only)
    Every synced change to every character: who changed what, and when.
    Search, filter by kind of change or by character, click to open a profile.
]]
local _, ns = ...
local W = ns.Widgets
local AV = {}
ns.AuditView = AV

local ROW_H = 22
local COLUMNS = {
    { key = "when",   label = "When",      width = 150 },
    { key = "who",    label = "Changed by", width = 120 },
    { key = "member", label = "Character", width = 130 },
    { key = "change", label = "Change",    width = 300, flex = true },
}

AV.filter = {}

function AV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    local search = CreateFrame("EditBox", "NootropicGMAuditSearch", page, "SearchBoxTemplate")
    search:SetSize(240, 20)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -33)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText("Search changes, names...") end
    search:HookScript("OnTextChanged", function(eb)
        AV.filter.text = eb:GetText()
        ns.Debounce("auditsearch", 0.15, function() AV:Refresh() end)
    end)
    self.searchBox = search

    local kind = W.Button(page, "All changes", 130, 22)
    kind:SetPoint("LEFT", search, "RIGHT", 10, 0)
    kind:SetScript("OnClick", function(btn) AV:ShowCategoryMenu(btn) end)
    self.kindButton = kind

    local group = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    group:SetSize(24, 24)
    group:SetPoint("LEFT", kind, "RIGHT", 8, 0)
    local glabel = group.Text or group.text
    if type(glabel) ~= "table" then
        glabel = group:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        glabel:SetPoint("LEFT", group, "RIGHT", 2, 1)
    end
    glabel:SetFontObject("GameFontHighlightSmall")
    glabel:SetText("Group changes")
    group:SetChecked(true)
    group:SetScript("OnClick", function() AV:Refresh() end)
    W.Tooltip(group, "Group changes", "Shows changes that were saved together (within the same 15-second batch) as one line. Hover a line to see every change in it.")
    group.Label = glabel
    self.groupCheck = group

    local who = W.Pill(page, 18, 22)
    who:SetPoint("LEFT", glabel, "RIGHT", 10, 0)
    who:SetScript("OnClick", function() AV:SetMember(nil) end)
    W.Tooltip(who, "Showing one character", "Click to show everyone.")
    who:Hide()
    self.memberPill = who

    self.retention = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.retention:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -38)
    self.count = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.count:SetPoint("RIGHT", self.retention, "LEFT", -12, 0)

    local inset = frame.Inset
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    header:SetHeight(24)
    self.header = header
    self.headers = {}
    for _, c in ipairs(COLUMNS) do
        local h = W.ColumnHeader(header, c.label, c.width)
        h:EnableMouse(false)
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
    view:SetElementInitializer("Button", function(row, e) AV:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 20)
    self.empty:SetWidth(420)

    page:SetScript("OnShow", function()
        AV:OnResize()
        AV:Refresh()
    end)
    ns:On("AUDIT_CHANGED", function()
        if page:IsVisible() then ns.Debounce("auditview", 0.2, function() AV:Refresh() end) end
    end)
end

function AV:OnResize()
    if not self.frame then return end
    local w = math.floor(self.frame:GetWidth() - AV.INSET)
    local fixed = 0
    for _, c in ipairs(COLUMNS) do if not c.flex then fixed = fixed + c.width end end
    local x = 0
    for _, c in ipairs(COLUMNS) do
        c.w = c.flex and math.max(160, w - fixed) or c.width
        c.x = x
        x = x + c.w
        local h = self.headers[c.key]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", c.x, 0)
        h:SetColumnWidth(c.w)
    end
    self.header:SetWidth(w)
    self.layoutVersion = (self.layoutVersion or 0) + 1
    if self.scrollBox.ForEachFrame then
        self.scrollBox:ForEachFrame(function(row) if row.entry then AV:InitRow(row, row.entry) end end)
    end
end
AV.INSET = 34

local function Text(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function AV:InitRow(row, e)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
        row.Stripe = row:CreateTexture(nil, "BACKGROUND")
        row.Stripe:SetAllPoints()
        row.Stripe:SetColorTexture(1, 1, 1, 0.035)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:GetHighlightTexture():SetAlpha(0.35)
        row.When = Text(row, "GameFontDisableSmall")
        row.Who = Text(row)
        row.Member = Text(row)
        row.Change = Text(row)
        row:SetScript("OnClick", function(self)
            local g = self.entry
            local m = g and g.memberCount == 1 and g.member
            if m and ns.Roster.byName[m] then
                ns.UI:SelectTab(ns.UI.TAB_ROSTER)
                ns.RosterView:Select(m)
            end
        end)
        row:SetScript("OnEnter", function(self)
            local g = self.entry
            if not g then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(#g.entries == 1 and ns.Audit:CategoryLabel(g.entries[1].typ) or (#g.entries .. " changes saved together"))
            for i, en in ipairs(g.entries) do
                if i > 20 then GameTooltip:AddLine(("...and %d more"):format(#g.entries - 20), 0.6, 0.6, 0.6) break end
                en.desc = en.desc or ns.Audit:Describe(en)
                local who = (g.memberCount > 1 and en.member) and (ns.ShortName(en.member) .. ": ") or ""
                GameTooltip:AddLine(who .. en.desc, 1, 1, 1, true)
            end
            GameTooltip:AddDoubleLine("Changed by", ns.ShortName(g.author or "?"), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("When", ns.FormatDate(g.t), 1, 0.82, 0, 1, 1, 1)
            if g.memberCount == 1 then GameTooltip:AddLine("Click to open " .. ns.ShortName(g.member) .. "'s profile.", 0.5, 0.5, 0.5) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if row.layoutVersion ~= self.layoutVersion then
        local cells = { when = row.When, who = row.Who, member = row.Member, change = row.Change }
        for _, c in ipairs(COLUMNS) do
            local fs = cells[c.key]
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", c.x + 8, 0)
            fs:SetWidth(c.w - 12)
        end
        row.layoutVersion = self.layoutVersion
    end
    -- e is a group of one or more changes saved together
    row.entry = e
    row.Stripe:SetShown(e._stripe)
    row.When:SetText(ns.FormatDate(e.t))
    row.Who:SetText(ns.ShortName(e.author or "?"))
    if e.memberCount == 1 then
        local entry = ns.Roster.byName[e.member]
        row.Member:SetText(ns.ShortName(e.member))
        if entry then row.Member:SetTextColor(ns.ClassColor(entry.classFile)) else row.Member:SetTextColor(0.7, 0.7, 0.7) end
    elseif e.memberCount > 1 then
        row.Member:SetText(e.memberCount .. " characters")
        row.Member:SetTextColor(0.9, 0.9, 0.9)
    else
        row.Member:SetText("|cff6d6d6d-|r")
    end
    row.Change:SetText(ns.Audit:Summary(e))
end

function AV:ShowCategoryMenu(owner)
    local items = { { text = "Show", isTitle = true } }
    items[#items + 1] = {
        text = "All changes", radio = true,
        checked = function() return AV.filter.category == nil end,
        func = function() AV.filter.category = nil; AV:Refresh() end,
    }
    for _, c in ipairs(ns.Audit.CATEGORIES) do
        items[#items + 1] = {
            text = c.label, radio = true,
            checked = function() return AV.filter.category == c.key end,
            func = function() AV.filter.category = c.key; AV:Refresh() end,
        }
    end
    W.ShowMenu(owner, items)
end

-- Show only one character's history (nil = everyone).
function AV:SetMember(full)
    self.filter.member = full
    self:Refresh()
end

function AV:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    local entries = ns.Audit:Entries(self.filter)
    local list = self.groupCheck:GetChecked() and ns.Audit:Group(entries) or ns.Audit:Ungrouped(entries)
    for i, g in ipairs(list) do g._stripe = (i % 2 == 0) end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)

    self.kindButton:SetText(self.filter.category and ns.Audit:CategoryLabel(self.filter.category) or "All changes")
    if self.filter.member then
        self.memberPill:SetLabel(ns.ShortName(self.filter.member) .. "  x")
        self.memberPill:Show()
    else
        self.memberPill:Hide()
    end
    if #list ~= #entries then
        self.count:SetText(("%d changes in %d groups"):format(#entries, #list))
    else
        self.count:SetText(("%d changes"):format(#entries))
    end
    self.retention:SetText(("Keeping %d days  (Options)"):format(ns.DB:Settings().auditDays or 30))

    if not ns.IsOfficer() then
        self.empty:SetText("Only officers can view the audit.")
    elseif #list == 0 then
        self.empty:SetText("No changes recorded yet. Changes to tags, ratings, mains and alts, specs, professions and the officer log appear here.")
    else
        self.empty:SetText("")
    end
end
