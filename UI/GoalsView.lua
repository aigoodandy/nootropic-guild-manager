--[[
    Nootropic Guild Manager - Goal page and goal form (on the Insights tab)
    Shown in the Insights tab's right-hand panel when a goal is picked from the
    list (UI/PollsView.lua keeps the list and decides what's shown):
      page   title, description, target date, a big bar (members matching /
             target), a bar for each part, who counts, and who's almost
             there (level goals)
      form   two pages: Settings (title, description, filter chips, target,
             target date, parts, who can see it) and a Preview of the page
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local GV = {}
ns.GoalsView = GV

local MAX_NAMES = 40
local BAR_H, PART_BAR_H, PART_H = 26, 20, 36
local CHART_H = 130

-- the character panel's skill bar look (UI/Widgets.lua)
local function Bar(parent, height) return W.StatBar(parent, height) end

-- "Asper, Marc, Shamandy" in class colors (and "and 3 more").
local function NameList(members, withLevel)
    local parts = {}
    for i = 1, math.min(MAX_NAMES, #members) do
        local e = members[i]
        parts[i] = ("|c%s%s|r"):format(ns.ClassHex(e.classFile), e.short) .. (withLevel and (" |cff9d9d9d" .. e.level .. "|r") or "")
    end
    local text = table.concat(parts, ", ")
    if #members > MAX_NAMES then text = text .. (" and %d more"):format(#members - MAX_NAMES) end
    return text
end

local function DueText(due)
    if not due then return "no target date" end
    local days = math.floor((due - ns.DB:Now()) / 86400 + 0.5)
    local when = date("%a %b %d", due)
    if days > 1 then return ("target %s (in %d days)"):format(when, days) end
    if days == 1 then return ("target %s (tomorrow)"):format(when) end
    if days == 0 then return ("target %s (today)"):format(when) end
    return ("target %s |cffff6060(%d days ago)|r"):format(when, -days)
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
function GV:Build(panel)
    local PV = ns.PollsView
    local page = CreateFrame("Frame", nil, panel)
    page:SetAllPoints()
    page:Hide()
    self.page = page
    -- everything but the buttons scrolls
    local scroll = W.TryCreate("ScrollFrame", nil, page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 42)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(300, 10)
    scroll:SetScrollChild(p)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then p:SetWidth(w) end end)
    self.scroll, self.content = scroll, p

    local title, line = W.SectionHeader(p, "Guild Goal")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    self.header = title

    self.title = PV.Para(p, "GameFontHighlight")
    self.title:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    self.title:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.desc = PV.Para(p, "GameFontDisableSmall")
    self.desc:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.desc:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.status = PV.Para(p, "GameFontHighlightSmall")
    self.status:SetPoint("TOPLEFT", self.desc, "BOTTOMLEFT", 0, -4)
    self.status:SetPoint("RIGHT", p, "RIGHT", -14, 0)

    -- the main bar
    self.mainLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.mainLabel:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -14)
    self.mainLabel:SetPoint("RIGHT", p, "RIGHT", -120, 0)
    self.mainLabel:SetJustifyH("LEFT")
    self.mainLabel:SetWordWrap(false)
    self.mainCount = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.mainCount:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.mainCount:SetPoint("TOP", self.mainLabel, "TOP", 0, 0)
    self.mainBar = Bar(p, BAR_H)
    self.mainBar:SetPoint("TOPLEFT", self.mainLabel, "BOTTOMLEFT", 0, -4)
    self.mainBar:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.mainNote = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.mainNote:SetPoint("TOPLEFT", self.mainBar, "BOTTOMLEFT", 0, -4)

    -- parts
    self.partRows = {}
    for i = 1, ns.Goals.MAX_PARTS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(PART_H)
        r:SetPoint("TOPLEFT", self.mainNote, "BOTTOMLEFT", 0, -10 - (i - 1) * (PART_H + 4))
        r:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Label:SetPoint("TOPLEFT", 2, -2)
        r.Count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Count:SetPoint("TOPRIGHT", -2, -2)
        r.BarBg = Bar(r, PART_BAR_H)
        r.BarBg:SetPoint("BOTTOMLEFT", 0, 1)
        r.BarBg:SetPoint("BOTTOMRIGHT", 0, 1)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.filter then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.Label:GetText())
            GameTooltip:AddLine("Counted among the goal's members with: " .. self.filter, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.partRows[i] = r
    end

    -- progress over time: one point a day (Services/Goals.lua history)
    self.chartLabel = PV.Label(p, "Progress over time")
    self.chart = W.LineChart(p, CHART_H)
    self.chart:SetPoint("TOPLEFT", self.chartLabel, "BOTTOMLEFT", 0, -6)
    self.chart:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.chartNote = PV.Para(p, "GameFontDisableSmall")
    self.chartNote:SetPoint("TOPLEFT", self.chart, "BOTTOMLEFT", 2, -4)
    self.chartNote:SetPoint("RIGHT", p, "RIGHT", -14, 0)

    -- who counts, who's almost there
    self.whoLabel = PV.Label(p, "Who counts")
    self.who = PV.Para(p, "GameFontHighlightSmall")
    self.who:SetPoint("TOPLEFT", self.whoLabel, "BOTTOMLEFT", 0, -4)
    self.who:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.almostLabel = PV.Label(p, "")
    self.almostLabel:SetPoint("TOPLEFT", self.who, "BOTTOMLEFT", 0, -10)
    self.almost = PV.Para(p, "GameFontHighlightSmall")
    self.almost:SetPoint("TOPLEFT", self.almostLabel, "BOTTOMLEFT", 0, -4)
    self.almost:SetPoint("RIGHT", p, "RIGHT", -14, 0)

    local edit = W.Button(page, "Edit Goal", 100, 22)
    edit:SetPoint("BOTTOMLEFT", 12, 12)
    edit:SetScript("OnClick", function() if GV.goal then GV:ShowEditor(GV.goal) end end)
    local del = W.Button(page, DELETE or "Delete", 90, 22)
    del:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    del:SetScript("OnClick", function() if GV.goal then GV:Delete(GV.goal.id) end end)
    self.editBtn, self.deleteBtn = edit, del

    self:BuildEditor(panel)
end

-- Shows a goal's page. Bars go in PollsView's list so they grow in with the rest.
function GV:ShowGoal(id)
    local PV = ns.PollsView
    local pr = ns.Goals:Progress(id)
    if not pr then return false end
    local g = pr.goal
    self.goal = g
    self.header:SetText(g.vis == "o" and "Officer Goal" or g.vis == "m" and "My Goal" or "Guild Goal")
    self.title:SetText(g.title)
    self.desc:SetText(g.desc or "")
    self.status:SetText("|cff66bbffLive  -  " .. DueText(g.due) .. "|r" ..
        ((g.filter or "") ~= "" and ("  |cff9d9d9dFilters: " .. g.filter .. "|r") or ""))

    -- main bar: gold, green once reached
    self.mainLabel:SetText("Members")
    self.mainCount:SetText(("|cffffffff%d|r / %d  |cff9d9d9d%d%%|r"):format(pr.count, pr.target, pr.pct))
    local bar = self.mainBar.Bar
    if pr.done then bar:SetStatusBarColor(0.2, 0.8, 0.3) else bar:SetStatusBarColor(1, 0.75, 0.1) end
    PV.barTargets[bar] = math.min(1, pr.count / math.max(1, pr.target))
    bar:SetValue(PV.barTargets[bar])
    local left = pr.target - pr.count
    self.mainNote:SetText(pr.done and "|cff40ff40Goal reached!|r" or (left == 1 and "1 more to go." or (left .. " more to go.")))

    -- parts
    local last = self.mainNote
    for i, r in ipairs(self.partRows) do
        local part = pr.parts[i]
        if part then
            r.filter = part.filter
            r.Label:SetText(part.label)
            r.Count:SetText(("|cffffffff%d|r / %d"):format(part.count, part.need) .. (part.done and "  |cff40ff40done|r" or ""))
            local pb = r.BarBg.Bar
            local color = part.done and { 0.2, 0.8, 0.3 } or { D:TagColor(D:NextColor(i)) }
            pb:SetStatusBarColor(color[1], color[2], color[3])
            PV.barTargets[pb] = math.min(1, part.count / math.max(1, part.need))
            pb:SetValue(PV.barTargets[pb])
            r:Show()
            last = r
        else
            r:Hide()
        end
    end

    self.chartLabel:ClearAllPoints()
    self.chartLabel:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
    self:DrawHistory(pr)
    self.whoLabel:ClearAllPoints()
    self.whoLabel:SetPoint("TOPLEFT", self.chartNote, "BOTTOMLEFT", -2, -14)
    self.who:SetText(#pr.members > 0 and NameList(pr.members) or "|cff9d9d9dNobody yet.|r")
    if pr.almost then
        self.almostLabel:SetText(("Almost there  |cff9d9d9d(level %d+)|r"):format(pr.almostFrom))
        self.almost:SetText(#pr.almost > 0 and NameList(pr.almost, true) or "|cff9d9d9dNobody close yet.|r")
        self.almostLabel:Show()
        self.almost:Show()
    else
        self.almostLabel:Hide()
        self.almost:Hide()
    end

    local editable = ns.Goals:CanEdit(g)
    self.editBtn:SetShown(editable)
    self.deleteBtn:SetShown(editable)

    -- a different goal starts at the top; the page is as tall as its content
    if id ~= self.shownId then
        self.scroll:SetVerticalScroll(0)
        self.shownId = id
    end
    local function Fit()
        local lowest = self.almost:IsShown() and self.almost or self.who
        local top, bottom = self.content:GetTop(), lowest:GetBottom()
        if top and bottom then self.content:SetHeight(math.max(10, top - bottom + 16)) end
    end
    Fit()
    C_Timer.After(0, function() if self.page:IsVisible() then Fit() end end)
    return true
end

-- The progress line: one point a day from the saved history, today's
-- point live, the target dashed across and, with a target date, the pace
-- that would reach it.
function GV:DrawHistory(pr)
    local GL, g = ns.Goals, pr.goal
    local today = GL.Day(ns.DB:Now())
    local points = {}
    for _, h in ipairs(GL:History(g.id)) do
        if h.day < today then points[#points + 1] = { x = h.day, y = h.count } end
    end
    points[#points + 1] = { x = today, y = pr.count } -- today, as it is now
    local first = points[1].x
    local dueDay = g.due and GL.Day(g.due)
    local xMax = math.max(today, dueDay or today)
    local yMax = 0
    for _, pt in ipairs(points) do yMax = math.max(yMax, pt.y) end

    local pace
    if dueDay and dueDay > first and not pr.done then
        pace = { first, points[1].y, dueDay, g.target }
    end
    local function Day(x) return date("!%b %d", x * 86400) end
    self.chart:SetData({
        points = points, xMin = first, xMax = xMax, yMax = yMax, target = g.target, pace = pace,
        color = pr.done and { 0.2, 0.8, 0.3 } or { 1, 0.75, 0.1 },
        xLabel = Day,
        tip = function(pt)
            local when = pt.x == today and "Today" or date("!%a %b %d", pt.x * 86400)
            return when, ("%d of %d members"):format(pt.y, g.target)
        end,
    })

    -- under the chart: how it's going
    local note
    if #points < 2 then
        note = "The line adds a point each day you log in, starting today."
    elseif pace and today <= dueDay then
        local expected = points[1].y + (g.target - points[1].y) * (today - first) / (dueDay - first)
        expected = math.floor(expected + 0.5)
        if pr.count >= expected then
            note = ("|cff40ff40On pace|r: %d now, about %d needed by today."):format(pr.count, expected)
        else
            note = ("|cffff9933Behind pace|r: %d now, about %d needed by today."):format(pr.count, expected)
        end
    elseif dueDay and today > dueDay and not pr.done then
        note = "|cffff6060The target date has passed.|r"
    else
        note = ("Since %s. One point a day, from the days you logged in."):format(date("!%b %d", first * 86400))
    end
    self.chartNote:SetText(note)
end

------------------------------------------------------------------------
-- Form: Settings (What, Who counts, Target, Parts, Who can see it) and a
-- Preview of the goal's page, counted from the roster as it is now. The
-- same shell as the poll form (FormKit.Form).
------------------------------------------------------------------------
local FORM_W = 290
local PREVIEW_PART_H = 30

local VIS_HINTS = {
    c = "Shared with everyone in the guild running the addon.",
    o = "Shared with officers only. Guildmates never receive it.",
    m = "Kept in your copy of the addon; nobody else sees it.",
}

local function Join(a, b) return ns.Trim((a or "") .. " " .. (b or "")) end

function GV:BuildEditor(panel)
    local PV, GL, FK = ns.PollsView, ns.Goals, ns.FormKit
    local form = FK.Form(panel, {
        title = "New Goal", previewLabel = "Preview",
        onSave = function() GV:Save() end,
        onCancel = function()
            PV.mode = nil
            PV:Refresh()
        end,
        onDelete = function() GV:Delete(GV.editing) end,
        onPage = function(page)
            if page ~= "preview" then return end
            for _, box in ipairs(GV.boxes) do box:ClearFocus() end
            GV:RefreshPreview()
        end,
    })
    self.gForm, self.form = form, form.frame
    local s = form.settings
    local function ClearError() form.err:SetText("") end

    ---------------- What ----------------
    local what = FK.Section(s, "What", s)
    what:SetPoint("TOPLEFT", 14, -2)
    local tLabel = PV.Label(s, "Title")
    tLabel:SetPoint("TOPLEFT", 14, -24)
    self.fTitle = PV.Input(s, FORM_W - 6, GL.TITLE_MAX)
    self.fTitle:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 6, -2)
    self.fTitle:HookScript("OnTextChanged", ClearError)
    local dLabel, desc = FK.Description(s, FORM_W, GL.DESC_MAX)
    dLabel:SetPoint("TOPLEFT", 14, -66)
    self.fDesc = desc

    ---------------- Who counts ----------------
    local who = FK.Section(s, "Who counts", s)
    who:SetPoint("TOPLEFT", 14, -130)
    self.fFilter = PV.Input(s, FORM_W - 6, GL.FILTER_MAX)
    W.Tooltip(self.fFilter, "Who counts", "The same words as the roster search; every one must match.",
        "level>=60  is:main  class:warrior  role:tank  rank:raider  tag:raiding  prof:alchemy")
    self.fChips = FK.FilterChips(s, FORM_W, self.fFilter, function() GV:RefreshEditor() end)
    self.fChips:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -8)

    ---------------- Target ----------------
    local target = FK.Section(s, "Target", s)
    target:SetPoint("TOPLEFT", self.fChips, "BOTTOMLEFT", 0, -10)
    local needLabel = PV.Label(s, "Members needed")
    needLabel:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -12)
    self.fTarget = PV.Input(s, 40, 3, true)
    self.fTarget:SetPoint("LEFT", needLabel, "LEFT", 122, 0)
    self.fTarget:HookScript("OnTextChanged", ClearError)
    local dueLabel = PV.Label(s, "Target date in")
    dueLabel:SetPoint("TOPLEFT", needLabel, "BOTTOMLEFT", 0, -16)
    self.fDays = PV.Input(s, 40, 3, true)
    self.fDays:SetPoint("LEFT", dueLabel, "LEFT", 122, 0)
    self.fDays:HookScript("OnTextChanged", function() GV:RefreshEditor() end)
    W.Tooltip(self.fDays, "Target date (optional)", "How many days from today. Leave empty for no date.")
    local days = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    days:SetPoint("LEFT", self.fDays, "RIGHT", 8, 0)
    days:SetText("days  |cff9d9d9d(empty: no date)|r")
    self.fDue = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.fDue:SetPoint("TOPLEFT", dueLabel, "BOTTOMLEFT", 0, -10)

    ---------------- Parts ----------------
    local parts = FK.Section(s, "Parts  |cff9d9d9d(optional: smaller targets among them)|r", s)
    parts:SetPoint("TOPLEFT", self.fDue, "BOTTOMLEFT", 0, -14)
    local function Heading(text, x)
        local fs = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", parts, "BOTTOMLEFT", x, -8)
        fs:SetText(text)
    end
    Heading("Name", 2)
    Heading("Who (a filter)", 92)
    Heading("Need", 270)
    self.fParts = {}
    local lastRow
    for i = 1, GL.MAX_PARTS do
        local name = PV.Input(s, 80, 24)
        name:SetPoint("TOPLEFT", parts, "BOTTOMLEFT", 6, -24 - (i - 1) * 24)
        local filter = PV.Input(s, 140, GL.FILTER_MAX)
        filter:SetPoint("LEFT", name, "RIGHT", 10, 0)
        local plus = W.Button(s, "+", 22, 20)
        plus:SetPoint("LEFT", filter, "RIGHT", 2, 0)
        plus:SetScript("OnClick", function(btn) PV:FilterMenu(btn, filter, function() ClearError() end) end)
        W.Tooltip(plus, "Add a filter", "Pick what this part counts, like Role > Tank.")
        local need = PV.Input(s, 30, 3, true)
        need:SetPoint("LEFT", plus, "RIGHT", 14, 0)
        W.Tooltip(name, "Part name", "For example: Tanks")
        W.Tooltip(filter, "Part filter", "Who counts for this part, among the goal's members. For example: role:tank")
        for _, box in ipairs({ name, filter, need }) do box:HookScript("OnTextChanged", ClearError) end
        self.fParts[i] = { name = name, filter = filter, need = need }
        lastRow = name
    end

    ---------------- Who can see it ----------------
    local vis = FK.Section(s, "Who can see it", s)
    vis:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", -6, -14)
    local options = {}
    for _, v in ipairs(ns.Stats.VISIBILITY) do
        options[#options + 1] = { key = v.key, label = v.key == "c" and "Everyone" or v.label }
    end
    self.fVisSeg = FK.Segment(s, FORM_W, options, function() return GV.fVis end, function(key)
        GV.fVis = key
        GV:RefreshEditor()
    end)
    self.fVisSeg:SetPoint("TOPLEFT", vis, "BOTTOMLEFT", 0, -8)
    self.fVisHint = PV.Para(s, "GameFontDisableSmall", FORM_W)
    self.fVisHint:SetPoint("TOPLEFT", self.fVisSeg, "BOTTOMLEFT", 2, -4)
    form:FitSettings(self.fVisHint)

    -- tab moves through the boxes
    self.boxes = { self.fTitle, desc, self.fTarget, self.fDays }
    for _, part in ipairs(self.fParts) do
        self.boxes[#self.boxes + 1] = part.name
        self.boxes[#self.boxes + 1] = part.filter
        self.boxes[#self.boxes + 1] = part.need
    end
    for i, box in ipairs(self.boxes) do box.nextBox = self.boxes[i + 1] or self.boxes[1] end

    ---------------- Preview: the goal's page ----------------
    local pv = form.preview
    local prev = FK.Section(pv, "Preview", pv)
    prev:SetPoint("TOPLEFT", 4, -2)
    self.pNote = pv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.pNote:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    self.pNote:SetText("counted from the roster now")
    prev.Line:SetPoint("LEFT", self.pNote, "RIGHT", 6, 0)
    self.pTitle = PV.Para(pv, "GameFontHighlight")
    self.pTitle:SetPoint("TOPLEFT", 4, -24)
    self.pTitle:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
    self.pDesc = PV.Para(pv, "GameFontDisableSmall")
    self.pDesc:SetPoint("TOPLEFT", self.pTitle, "BOTTOMLEFT", 0, -4)
    self.pDesc:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
    self.pStatus = PV.Para(pv, "GameFontHighlightSmall")
    self.pStatus:SetPoint("TOPLEFT", self.pDesc, "BOTTOMLEFT", 0, -4)
    self.pStatus:SetPoint("RIGHT", pv, "RIGHT", -4, 0)

    local mainLabel = pv:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainLabel:SetPoint("TOPLEFT", self.pStatus, "BOTTOMLEFT", 0, -12)
    mainLabel:SetText("Members")
    self.pCount = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.pCount:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
    self.pCount:SetPoint("TOP", mainLabel, "TOP", 0, 0)
    self.pBar = Bar(pv, BAR_H)
    self.pBar:SetPoint("TOPLEFT", mainLabel, "BOTTOMLEFT", 0, -4)
    self.pBar:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
    self.pLeft = pv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.pLeft:SetPoint("TOPLEFT", self.pBar, "BOTTOMLEFT", 0, -4)

    self.pParts = {}
    for i = 1, GL.MAX_PARTS do
        local r = CreateFrame("Frame", nil, pv)
        r:SetHeight(PREVIEW_PART_H)
        r:SetPoint("TOPLEFT", self.pLeft, "BOTTOMLEFT", 0, -8 - (i - 1) * (PREVIEW_PART_H + 4))
        r:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
        r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Label:SetPoint("TOPLEFT", 2, -1)
        r.Count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Count:SetPoint("TOPRIGHT", -2, -1)
        r.BarBg = Bar(r, 14)
        r.BarBg:SetPoint("BOTTOMLEFT", 0, 1)
        r.BarBg:SetPoint("BOTTOMRIGHT", 0, 1)
        self.pParts[i] = r
    end
    self.pWhoLabel = PV.Label(pv, "Who counts now")
    self.pWho = PV.Para(pv, "GameFontHighlightSmall")
    self.pWho:SetPoint("TOPLEFT", self.pWhoLabel, "BOTTOMLEFT", 0, -4)
    self.pWho:SetPoint("RIGHT", pv, "RIGHT", -4, 0)
    if self.pWho.SetMaxLines then self.pWho:SetMaxLines(4) end
end

-- goal: the goal to edit, or nil for a new one.
function GV:ShowEditor(goal)
    local PV = ns.PollsView
    if not ns.DB:Guild() then return end
    PV.mode = "goalForm"
    self.editing = goal and goal.id or nil
    local form = self.gForm
    form.header:SetText(goal and "Edit Goal" or "New Goal")
    self.fTitle:SetText(goal and goal.title or "")
    self.fDesc:SetText(goal and goal.desc or "")
    self.fFilter:SetText(goal and goal.filter or "")
    self.fChips:SetTextMode(false)
    self.fTarget:SetText(goal and tostring(goal.target) or "10")
    local days = goal and goal.due and math.max(0, math.floor((goal.due - ns.DB:Now()) / 86400 + 0.5))
    self.fDays:SetText(days and tostring(days) or "")
    for i, row in ipairs(self.fParts) do
        local part = goal and goal.parts[i]
        row.name:SetText(part and part.label or "")
        row.filter:SetText(part and part.filter or "")
        row.need:SetText(part and tostring(part.need) or "")
    end
    self.fVis = goal and goal.vis or (ns.IsOfficer() and "c" or "m")
    form.deleteBtn:SetShown(goal and ns.Goals:CanEdit(goal) or false)
    form.err:SetText("")
    form.scroll:SetVerticalScroll(0)
    form:ShowPage("settings")
    PV:Refresh()
    self.fTitle:SetFocus()
end

function GV:RefreshEditor()
    local form = self.gForm
    self.fChips:Refresh()
    local n, total = ns.Stats:MatchCount(self.fFilter:GetText())
    self.fChips.Matches:SetText(("Matches %d of %d members"):format(n, total))
    self.fDesc.UpdateCount()
    local days = tonumber(self.fDays:GetText())
    self.fDue:SetText(days and ("Target date: " .. date("%a %b %d", ns.DB:Now() + days * 86400)) or "No target date.")
    if self.fVis ~= "m" and not ns.IsOfficer() then self.fVis = "m" end
    local officer = ns.IsOfficer()
    self.fVisSeg:Refresh(function(key) return key == "m" or officer end)
    self.fVisHint:SetText(VIS_HINTS[self.fVis] or "")
    form.err:SetText("")
    form:FitSettings()
    if form.page == "preview" then self:RefreshPreview() end
end

-- The preview: the goal's page as it would show now.
function GV:RefreshPreview()
    local title = ns.Trim(self.fTitle:GetText() or "")
    self.pTitle:SetText(title ~= "" and title or "|cff9d9d9dYour goal|r")
    self.pDesc:SetText(ns.Trim(self.fDesc:GetText() or ""))
    local days = tonumber(self.fDays:GetText())
    self.pStatus:SetText("|cff66bbffLive  -  " .. DueText(days and (ns.DB:Now() + days * 86400)) .. "|r")

    local filter = self.fFilter:GetText() or ""
    local members = ns.Roster:Query(filter)
    table.sort(members, function(a, b) return a.short < b.short end)
    local target = math.max(1, math.floor(tonumber(self.fTarget:GetText()) or 1))
    local n = #members
    local pct = math.min(100, math.floor(n * 100 / target + 0.5))
    self.pCount:SetText(("|cffffffff%d|r / %d  |cff9d9d9d%d%%|r"):format(n, target, pct))
    local bar = self.pBar.Bar
    if n >= target then bar:SetStatusBarColor(0.2, 0.8, 0.3) else bar:SetStatusBarColor(1, 0.75, 0.1) end
    bar:SetValue(math.min(1, n / target))
    local left = target - n
    self.pLeft:SetText(n >= target and "|cff40ff40Goal reached!|r" or (left == 1 and "1 more to go." or (left .. " more to go.")))

    local last, shown = self.pLeft, 0
    for _, row in ipairs(self.fParts) do
        local label = ns.Trim(row.name:GetText() or "")
        local pf = ns.Trim(row.filter:GetText() or "")
        if label ~= "" or pf ~= "" then
            shown = shown + 1
            local r = self.pParts[shown]
            local need = math.max(0, math.floor(tonumber(row.need:GetText()) or 0))
            local count = pf ~= "" and #ns.Roster:Query(Join(filter, pf)) or 0
            local done = need > 0 and count >= need
            r.Label:SetText(label ~= "" and label or "|cff9d9d9d(no name)|r")
            r.Count:SetText(("|cffffffff%d|r / %d"):format(count, need) .. (done and "  |cff40ff40done|r" or ""))
            local cr, cg, cb
            if done then cr, cg, cb = 0.2, 0.8, 0.3 else cr, cg, cb = D:TagColor(D:NextColor(shown)) end
            r.BarBg.Bar:SetStatusBarColor(cr, cg, cb)
            r.BarBg.Bar:SetValue(need > 0 and math.min(1, count / need) or 0)
            r:Show()
            last = r
        end
    end
    for i = shown + 1, #self.pParts do self.pParts[i]:Hide() end
    self.pWhoLabel:ClearAllPoints()
    self.pWhoLabel:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
    self.pWho:SetText(n > 0 and NameList(members) or "|cff9d9d9dNobody yet.|r")
end

-- Asks, then deletes a goal.
function GV:Delete(id)
    local g = id and ns.Goals:Get(id)
    if not g then return end
    local PV = ns.PollsView
    local who = g.vis == "m" and "" or (g.vis == "c" and " for everyone" or " for all officers")
    W.Confirm(("Delete the goal \"%s\"%s?"):format(g.title, who), function()
        local ok, err = ns.Goals:Delete(g.id)
        if not ok and err then
            ns:Print("|cffff5555" .. err .. "|r")
        else
            PV.selected, PV.mode = nil, nil
            PV:Refresh()
        end
    end)
end

function GV:Save()
    local parts = {}
    for _, row in ipairs(self.fParts) do
        parts[#parts + 1] = { label = row.name:GetText(), filter = row.filter:GetText(), need = row.need:GetText() }
    end
    local days = tonumber(self.fDays:GetText())
    local id, err = ns.Goals:Save(self.editing, {
        title = self.fTitle:GetText(), desc = self.fDesc:GetText(), filter = self.fFilter:GetText(),
        target = self.fTarget:GetText(), due = days and (ns.DB:Now() + days * 86400) or nil, parts = parts,
        vis = self.fVis,
    })
    if not id then
        -- every check is about the Settings page
        if self.gForm.page ~= "settings" then self.gForm:ShowPage("settings") end
        self.gForm.err:SetText(err or "Couldn't save the goal.")
        return
    end
    for _, box in ipairs(self.boxes) do box:ClearFocus() end
    ns.PollsView:Select("goal:" .. id)
end
