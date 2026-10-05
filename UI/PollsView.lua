--[[
    Nootropic Guild Manager - Polls tab
    Everyone: see the guild's polls, vote (and change your vote) until a poll
    closes, and see the results, also after it closes.
    Officers: create polls, close voting early, delete polls.
    Guild stats (Services/Stats.lua) are listed with the polls and shown the
    same way, without voting: result rows with bars, and a pie chart.
    Hovering a row highlights its slice, and hovering a slice its row.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local PV = {}
ns.PollsView = PV

local ROW_H = 46        -- a poll in the list
local STAT_ROW_H = 24   -- a stat in the list
local HEADER_H = 22     -- a section heading in the list
local LIST_W = 230
local PANEL_W = 340     -- the create form's width (the panel itself is wider)
local IW = PANEL_W - 28
local OPTION_H = 38
local STAT_H = 28       -- a stat result row: its name above a full-width bar
local MAX_STAT_ROWS = 10 -- more would run into the buttons; the footer says "Showing the top 10"
local PIE = 200         -- the pie's starting size; it's resized to the room left
local PIE_MAX, PIE_MIN = 240, 80
local STAT_PREFIX = "stat:"

local GOAL_PREFIX = "goal:"

local function StatId(key)
    return type(key) == "string" and key:sub(1, #STAT_PREFIX) == STAT_PREFIX and key:sub(#STAT_PREFIX + 1) or nil
end

local function GoalId(key)
    return type(key) == "string" and key:sub(1, #GOAL_PREFIX) == GOAL_PREFIX and key:sub(#GOAL_PREFIX + 1) or nil
end

local function Para(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if width then fs:SetWidth(width) end
    fs:SetSpacing(2)
    return fs
end

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function Input(parent, width, maxLetters, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetMaxLetters(maxLetters)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTabPressed", function(self)
        if self.nextBox then self.nextBox:SetFocus() end
    end)
    return eb
end
-- shared with the goal page and form (UI/GoalsView.lua)
PV.Para, PV.Label, PV.Input = Para, Label, Input

-- "Open - closes in 2d 3h" / "Closed Oct 03 - results kept 5 more days"
local function StatusText(p)
    local now = ns.DB:Now()
    if p.open then
        return ("|cff40ff40Open|r - closes in %s"):format(ns.Polls.FormatSpan(p.closeAt - now))
    end
    local left = p.expireAt - now
    local keep = left >= 86400 and ("results kept %s more"):format(ns.Polls.FormatSpan(left))
        or ("results removed in %s"):format(ns.Polls.FormatSpan(left))
    return ("|cffff6060Closed|r %s - %s"):format(date("%b %d", p.closeAt), keep)
end

local function VotesText(n) return n == 1 and "1 vote" or (n .. " votes") end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function PV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame
    page:SetScript("OnShow", function()
        PV.animateNext = true -- the chart grows in when the tab opens
        PV:Refresh()
    end)

    self.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 84, -38)
    self.sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sub:SetPoint("LEFT", self.summary, "RIGHT", 14, 0)

    local new = W.Button(page, "New Poll", 100, 22)
    new:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    new:SetScript("OnClick", function() PV:ShowCreate() end)
    W.Tooltip(new, "New poll", "Ask the guild a question with 2 to 6 answers.", "Officers only.")
    self.newBtn = new

    local newStat = W.Button(page, "New Stat", 100, 22)
    newStat:SetPoint("RIGHT", new, "LEFT", -6, 0)
    newStat:SetScript("OnClick", function() PV:ShowStatEditor(nil) end)
    W.Tooltip(newStat, "New stat", "Count guildmates your way: choose what to count by and add filters.",
        "Officers can share stats with the guild or with officers; anyone can make one just for themselves.")
    self.newStatBtn = newStat

    local newGoal = W.Button(page, "New Goal", 100, 22)
    newGoal:SetPoint("RIGHT", newStat, "LEFT", -6, 0)
    newGoal:SetScript("OnClick", function() ns.GoalsView:ShowEditor(nil) end)
    W.Tooltip(newGoal, "New goal", "Set a target for the guild, like \"10 level 60 mains for Molten Core\", with smaller parts such as 2 tanks.",
        "Officers can share goals with the guild or with officers; anyone can make one just for themselves.")
    self.newGoalBtn = newGoal

    local inset = frame.Inset
    self:BuildList(page, inset)
    self:BuildPanel(page, inset)

    local function changed()
        if page:IsVisible() then ns.Debounce("pollsview", 0.1, function() PV:Refresh() end) end
    end
    ns:On("STATS_CHANGED", changed)
    ns:On("POLLS_CHANGED", changed)
    ns:On("POLLS_TICK", changed)
    ns:On("OFFICER_CHANGED", changed)
    -- stats follow the roster, profiles and kudos
    local function statsChanged()
        -- stats and goals (and the goals' percentages in the list) follow the roster
        if page:IsVisible() then
            ns.Debounce("pollsview", 0.3, function() PV:Refresh() end)
        end
    end
    ns:On("ROSTER_UPDATED", statsChanged)
    ns:On("KUDOS_CHANGED", statsChanged)
    ns:On("LINKS_CHANGED", statsChanged)
end

function PV:BuildList(page, inset)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 4)
    box:SetWidth(LIST_W)
    self.listBox = box

    local scrollBox = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
    local scrollBar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, item)
            return item.header and HEADER_H or item.stat and STAT_ROW_H or ROW_H
        end)
    else
        view:SetElementExtent(ROW_H)
    end
    view:SetElementInitializer("Button", function(row, item) PV:InitRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox
end

local function BuildListRow(row)
    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetColorTexture(1, 1, 1, 0.035)
    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetAllPoints()
    row.Selected:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    row.Selected:SetBlendMode("ADD")
    row.Selected:SetVertexColor(1, 0.82, 0, 0.45)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.3)
    -- poll
    row.Question = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Question:SetPoint("TOPLEFT", 10, -7)
    row.Question:SetPoint("RIGHT", -64, 0)
    row.Question:SetJustifyH("LEFT")
    row.Question:SetWordWrap(false)
    row.Votes = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Votes:SetPoint("TOPRIGHT", -8, -8)
    row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Status:SetPoint("TOPLEFT", row.Question, "BOTTOMLEFT", 0, -5)
    row.Status:SetPoint("RIGHT", -64, 0)
    row.Status:SetJustifyH("LEFT")
    row.Status:SetWordWrap(false)
    row.Mine = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.Mine:SetPoint("TOPRIGHT", row.Votes, "BOTTOMRIGHT", 0, -5)
    -- stat
    row.StatName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.StatName:SetPoint("LEFT", 12, 0)
    row.StatName:SetPoint("RIGHT", -64, 0)
    row.StatName:SetJustifyH("LEFT")
    row.StatName:SetWordWrap(false)
    row.Live = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.Live:SetPoint("RIGHT", -8, 0)
    -- section heading
    row.Header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.Header:SetPoint("BOTTOMLEFT", 6, 4)
    row.HeaderLine = row:CreateTexture(nil, "ARTWORK")
    row.HeaderLine:SetColorTexture(1, 0.82, 0, 0.22)
    row.HeaderLine:SetHeight(1)
    row.HeaderLine:SetPoint("LEFT", row.Header, "RIGHT", 6, 0)
    row.HeaderLine:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if item and item.poll then
            PV:Select(item.poll.id)
        elseif item and item.stat then
            PV:Select(item.stat.key or (STAT_PREFIX .. item.stat.id))
        end
    end)
end

-- item: { header = text } | { poll = p } | { stat = { id, name } }
function PV:InitRow(row, item)
    if not row.built then
        row.built = true
        BuildListRow(row)
    end
    row.item = item
    local p, stat, header = item.poll, item.stat, item.header
    row:SetHeight(header and HEADER_H or stat and STAT_ROW_H or ROW_H)
    row:EnableMouse(not header)
    for _, part in ipairs({ row.Question, row.Votes, row.Status, row.Mine }) do part:SetShown(p ~= nil) end
    row.StatName:SetShown(stat ~= nil)
    row.Live:SetShown(stat ~= nil)
    row.Header:SetShown(header ~= nil)
    row.HeaderLine:SetShown(header ~= nil)
    row.Stripe:SetShown(item.stripe and not header)
    local key = p and p.id or stat and (stat.key or (STAT_PREFIX .. stat.id))
    row.Selected:SetShown(key ~= nil and key == self.selected and self.mode == "detail")
    if header then
        row.Header:SetText(header)
    elseif stat then
        row.StatName:SetText(stat.name)
        row.Live:SetText(stat.right or "live") -- a goal shows its progress
    else
        row.Question:SetText(p.question)
        if p.open then
            row.Question:SetTextColor(1, 0.82, 0)
        else
            row.Question:SetTextColor(0.7, 0.7, 0.7)
        end
        row.Status:SetText(StatusText(p))
        row.Votes:SetText(VotesText(p.total))
        if p.myVote then
            row.Mine:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t voted")
        elseif p.open then
            row.Mine:SetText("|cffffd100not voted|r")
        else
            row.Mine:SetText("")
        end
    end
end

------------------------------------------------------------------------
-- Right panel
------------------------------------------------------------------------
function PV:BuildPanel(page, inset)
    local panel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", self.listBox, "TOPRIGHT", 12, 0)
    panel:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
    panel:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0, 0, 0, 0.35)
    panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    self.panel = panel

    -- Nothing selected
    local info = CreateFrame("Frame", nil, panel)
    info:SetAllPoints()
    self.infoPane = info
    local ititle, iline = W.SectionHeader(info, "Guild Polls")
    ititle:SetPoint("TOPLEFT", 14, -12)
    iline:SetPoint("RIGHT", info, "RIGHT", -12, 0)
    self.infoText = Para(info, "GameFontHighlightSmall", IW)
    self.infoText:SetPoint("TOPLEFT", ititle, "BOTTOMLEFT", 0, -10)

    self:BuildDetail(panel)
    self:BuildCreate(panel)
    self:BuildStatEditor(panel)
    ns.GoalsView:Build(panel)
end

function PV:BuildDetail(panel)
    local d = CreateFrame("Frame", nil, panel)
    d:SetAllPoints()
    d:Hide()
    self.detailPane = d

    local title, line = W.SectionHeader(d, "Poll")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    self.dTitle = title

    self.dQuestion = Para(d, "GameFontHighlight")
    self.dQuestion:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    self.dQuestion:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    self.dStatus = Para(d, "GameFontHighlightSmall")
    self.dStatus:SetPoint("TOPLEFT", self.dQuestion, "BOTTOMLEFT", 0, -6)
    self.dStatus:SetPoint("RIGHT", d, "RIGHT", -14, 0)

    -- the pie, under the result rows (placed and sized in Refresh)
    local pie = W.PieChart(d, PIE)
    pie.OnSliceEnter = function(_, index) PV:HoverResult(index, "pie") end
    -- clicking a stat's slice opens those members in the roster, like its row
    pie:SetScript("OnMouseUp", function(self)
        local index = self:IndexAtCursor()
        local row = index and PV.stat and PV.stat.rows[index]
        if row and row.query then ns.UI:ShowRosterWithSearch(row.query) end
    end)
    self.pie = pie

    self:BuildStatRows(d)

    self.optionRows = {}
    for i = 1, ns.Polls.MAX_OPTIONS do
        local r = CreateFrame("Button", nil, d)
        r:SetHeight(OPTION_H - 4)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:GetHighlightTexture():SetAlpha(0.3)
        r.Check = r:CreateTexture(nil, "OVERLAY")
        r.Check:SetSize(14, 14)
        r.Check:SetPoint("TOPLEFT", 2, -2)
        r.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        r.Icon = r:CreateTexture(nil, "ARTWORK")
        r.Icon:SetSize(14, 14)
        r.Icon:SetPoint("TOPLEFT", 20, -2)
        r.Text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Text:SetPoint("TOPLEFT", 20, -3)
        r.Text:SetPoint("RIGHT", -70, 0)
        r.Text:SetJustifyH("LEFT")
        r.Text:SetWordWrap(false)
        r.Count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Count:SetPoint("TOPRIGHT", -2, -3)
        local barBg = CreateFrame("Frame", nil, r, "BackdropTemplate")
        barBg:SetPoint("BOTTOMLEFT", 20, 2)
        barBg:SetPoint("BOTTOMRIGHT", -2, 2)
        barBg:SetHeight(12)
        barBg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        barBg:SetBackdropColor(0, 0, 0, 0.6)
        barBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        local bar = CreateFrame("StatusBar", nil, barBg)
        bar:SetPoint("TOPLEFT", 2, -2)
        bar:SetPoint("BOTTOMRIGHT", -2, 2)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, 1)
        r.Bar = bar
        r:SetScript("OnClick", function(self) PV:OnVote(self.index) end)
        r:SetScript("OnEnter", function(self) PV:HoverResult(self.index, "row") end)
        r:SetScript("OnLeave", function() PV:HoverResult(nil, "row") end)
        r.index = i
        self.optionRows[i] = r
    end

    self.dFooter = Para(d, "GameFontDisableSmall")
    self.dFooter:SetPoint("RIGHT", d, "RIGHT", -14, 0)

    local close = W.Button(d, "Close Voting", 120, 22)
    close:SetPoint("BOTTOMLEFT", 12, 12)
    close:SetScript("OnClick", function()
        local p = PV.current
        if not p then return end
        W.Confirm(("Close voting on \"%s\" now?\nThe results stay visible."):format(p.question), function()
            local ok, err = ns.Polls:CloseNow(p.id)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end)
    end)
    self.closeBtn = close
    local del = W.Button(d, DELETE or "Delete", 90, 22)
    del:SetPoint("LEFT", close, "RIGHT", 8, 0)
    del:SetScript("OnClick", function()
        local p = PV.current
        if not p then return end
        W.Confirm(("Delete the poll \"%s\" and its results for everyone?"):format(p.question), function()
            local ok, err = ns.Polls:Delete(p.id)
            if not ok and err then
                ns:Print("|cffff5555" .. err .. "|r")
            else
                PV.selected = nil
                PV:Refresh()
            end
        end)
    end)
    self.deleteBtn = del
end

------------------------------------------------------------------------
-- Row looks: each poll answer's and stat row's color and icon
------------------------------------------------------------------------
-- Shows a row's icon on a texture (its chosen icon, or a class icon), or
-- hides it. Returns whether there is one.
local function SetRowIcon(tex, row)
    if row and row.icon then
        W.SetIcon(tex, row.icon)
    elseif row and row.classFile then
        W.SetClassIcon(tex, row.classFile)
    else
        tex:Hide()
        return false
    end
    tex:Show()
    return true
end

-- An icon button and a color swatch for one row in a form. get() returns
-- what the row shows now: { color (a palette number) or r, g, b, icon,
-- classFile }. set("icon", icon or false for none) / set("color", n) saves
-- a pick. Right-click the icon to show none.
local function LookControls(parent, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(44, 20)
    local icon = CreateFrame("Button", nil, f, "BackdropTemplate")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT")
    icon:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 1 })
    icon:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    icon.Tex = icon:CreateTexture(nil, "ARTWORK")
    icon.Tex:SetPoint("TOPLEFT", 1, -1)
    icon.Tex:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.Empty = icon:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    icon.Empty:SetPoint("CENTER")
    icon.Empty:SetText("+")
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    icon:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            set("icon", false)
            return
        end
        ns.IconPicker:Open(get().icon, function(chosen) set("icon", chosen) end, self)
    end)
    W.Tooltip(icon, "Icon", "Click to choose an icon (or paste one).", "Right-click to show no icon.")
    local swatch = CreateFrame("Button", nil, f, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    swatch:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)
    swatch:SetScript("OnClick", function(self)
        W.ShowColorMenu(self, function() return get().color end, function(i) set("color", i) end)
    end)
    swatch:SetScript("OnEnter", function(self)
        local l = get()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Color")
        if l.color then GameTooltip:AddLine(D:ColorName(l.color), D:TagColor(l.color)) end
        GameTooltip:AddLine("Click to choose.", 1, 1, 1)
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function f:Refresh()
        local l = get() or {}
        icon.Empty:SetShown(not SetRowIcon(icon.Tex, l))
        if l.r and not l.color then
            swatch:SetBackdropColor(l.r, l.g, l.b, 1)
        else
            swatch:SetBackdropColor(D:TagColor(l.color or 1))
        end
    end
    return f
end


-- Stat result rows: icon, name and count on top, a full-width bar under them
-- (the same layout as poll answers).
function PV:BuildStatRows(d)
    self.statRows = {}
    for i = 1, MAX_STAT_ROWS do
        local r = CreateFrame("Button", nil, d)
        r:SetHeight(STAT_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:GetHighlightTexture():SetAlpha(0.3)
        r.Icon = r:CreateTexture(nil, "ARTWORK")
        r.Icon:SetSize(14, 14)
        r.Icon:SetPoint("TOPLEFT", 2, -1)
        r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Label:SetPoint("TOPLEFT", 20, -2)
        r.Label:SetPoint("RIGHT", -80, 0)
        r.Label:SetJustifyH("LEFT")
        r.Label:SetWordWrap(false)
        r.Count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Count:SetPoint("TOPRIGHT", -2, -2)
        r.Count:SetJustifyH("RIGHT")
        local barBg = CreateFrame("Frame", nil, r, "BackdropTemplate")
        barBg:SetPoint("BOTTOMLEFT", 0, 1)
        barBg:SetPoint("BOTTOMRIGHT", 0, 1)
        barBg:SetHeight(12)
        barBg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        barBg:SetBackdropColor(0, 0, 0, 0.6)
        barBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        local bar = CreateFrame("StatusBar", nil, barBg)
        bar:SetPoint("TOPLEFT", 2, -2)
        bar:SetPoint("BOTTOMRIGHT", -2, 2)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, 1)
        r.Bar = bar
        r.index = i
        r:SetScript("OnClick", function(self)
            local row = PV.stat and PV.stat.rows[self.index]
            if row and row.query then ns.UI:ShowRosterWithSearch(row.query) end
        end)
        r:SetScript("OnEnter", function(self) PV:HoverResult(self.index, "row") end)
        r:SetScript("OnLeave", function() PV:HoverResult(nil, "row") end)
        self.statRows[i] = r
    end
end

------------------------------------------------------------------------
-- Hovering a result: the row and its pie slice light up together
------------------------------------------------------------------------
-- index: the answer / stat row (nil = nothing). from: "row" or "pie".
function PV:HoverResult(index, from)
    local rows = self.stat and self.statRows or self.optionRows
    for i, r in ipairs(rows) do
        if i == index then r:LockHighlight() else r:UnlockHighlight() end
    end
    self.pie:SetHighlight(index)
    if not index then
        GameTooltip:Hide()
        return
    end
    local owner = from == "pie" and self.pie or rows[index]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if self.stat then
        local s, row = self.stat, self.stat.rows[index]
        if not row then return end
        GameTooltip:AddLine(row.label, row.r, row.g, row.b)
        local pct = s.total > 0 and math.floor(row.count * 100 / s.total + 0.5) or 0
        GameTooltip:AddLine(("%d of %d %s (%d%%)"):format(row.count, s.total, s.pctOf, pct), 1, 1, 1)
        if row.tip then GameTooltip:AddLine(row.tip, 0.8, 0.8, 0.8, true) end
        if row.query and row.count > 0 then GameTooltip:AddLine("Click to see them in the roster.", 0.6, 0.85, 1) end
    else
        local p = self.current
        if not p then return end
        local n = p.counts[index] or 0
        local pct = p.total > 0 and math.floor(n * 100 / p.total + 0.5) or 0
        GameTooltip:AddLine(p.options[index] or "", 1, 1, 1, true)
        GameTooltip:AddLine(("%s (%d%%)"):format(VotesText(n), pct), 0.8, 0.8, 0.8)
        if p.open then
            GameTooltip:AddLine(p.myVote == index and "Your vote." or "Click to vote for this answer.", 0.6, 0.85, 1, true)
            if p.myVote and p.myVote ~= index then
                GameTooltip:AddLine("You can change your vote until the poll closes.", 0.7, 0.7, 0.7, true)
            end
        else
            GameTooltip:AddLine("Voting has closed.", 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Custom stat editor: title, count by, filters, who sees it
------------------------------------------------------------------------
local function DropButton(parent, width)
    local b = W.Button(parent, "", width, 22)
    b.Arrow = b:CreateTexture(nil, "OVERLAY")
    b.Arrow:SetSize(18, 18)
    b.Arrow:SetPoint("RIGHT", -4, 0)
    b.Arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    return b
end
PV.DropButton = DropButton

-- Distinct values among guild members, sorted: fn(e) returns a value or a list.
local function Present(fn)
    local seen, out = {}, {}
    for _, e in ipairs(ns.Roster.members or {}) do
        local v = fn(e)
        for _, x in ipairs(type(v) == "table" and v or { v }) do
            if x and x ~= "" and not seen[x] then
                seen[x] = true
                out[#out + 1] = x
            end
        end
    end
    table.sort(out)
    return out
end

-- Adds a filter word to a filter box (the stat form's unless given) and
-- runs onChange (the stat form's refresh unless given).
function PV:AddFilter(token)
    local box = self.filterTarget or self.sFilter
    local text = ns.Trim(box:GetText() or "")
    box:SetText(text == "" and token or (text .. " " .. token))
    if self.filterChanged then self.filterChanged() else self:RefreshStatEditor() end
end

-- The Add Filter menu. box / onChange: another form's filter box and refresh.
function PV:FilterMenu(owner, box, onChange)
    self.filterTarget, self.filterChanged = box, onChange
    local function Quote(s) return '"' .. s:lower() .. '"' end
    local function Sub(title, values, field)
        local items = {}
        for _, v in ipairs(values) do
            items[#items + 1] = { text = v, func = function() PV:AddFilter(field .. ":" .. Quote(v)) end }
        end
        if #items == 0 then items[1] = { text = "None in the guild", disabled = true } end
        return { text = title, submenu = items }
    end
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local atLeast, below = {}, {}
    for lv = 10, max, 10 do
        atLeast[#atLeast + 1] = { text = "Level " .. lv .. " and up", func = function() PV:AddFilter("level>=" .. lv) end }
        below[#below + 1] = { text = "Below level " .. lv, func = function() PV:AddFilter("level<" .. lv) end }
    end
    local items = {
        { text = "Add a filter", isTitle = true },
        Sub("Class", Present(function(e) return e.classFile ~= "" and D:ClassName(e.classFile) or nil end), "class"),
        Sub("Race", Present(function(e) return e.race end), "race"),
        Sub("Role", { "Tank", "Healer", "Damage" }, "role"),
        Sub("Rank", Present(function(e) return e.rank end), "rank"),
        Sub("Profession", Present(function(e)
            local t = {}
            for _, p in ipairs(e.profs or {}) do t[#t + 1] = p.name end
            return t
        end), "prof"),
        Sub("Tag", Present(function(e)
            local t = {}
            for _, tag in ipairs(e.tagList or {}) do t[#t + 1] = tag.name end
            return t
        end), "tag"),
        { text = "Level", submenu = { { text = "At least", submenu = atLeast }, { text = "Below", submenu = below } } },
        { divider = true },
        { text = "Mains only", func = function() PV:AddFilter("is:main") end },
        { text = "Alts only", func = function() PV:AddFilter("is:alt") end },
        { text = "Using the addon", func = function() PV:AddFilter("is:addon") end },
        { text = "Online now", func = function() PV:AddFilter("is:online") end },
    }
    W.ShowMenu(owner, items)
end

function PV:BuildStatEditor(panel)
    local ST = ns.Stats
    local c = CreateFrame("Frame", nil, panel)
    c:SetAllPoints()
    c:Hide()
    self.statPane = c

    local title, line = W.SectionHeader(c, "New Stat")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    self.sHeader = title

    local tLabel = Label(c, "Title")
    tLabel:SetPoint("TOPLEFT", 14, -36)
    self.sTitle = Input(c, IW - 8, ST.TITLE_MAX)
    self.sTitle:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 6, -2)
    self.sTitle:HookScript("OnTextChanged", function() PV.sError:SetText("") end)

    local gLabel = Label(c, "Count by")
    gLabel:SetPoint("TOPLEFT", 14, -82)
    local group = DropButton(c, 170)
    group:SetPoint("TOPLEFT", gLabel, "BOTTOMLEFT", 0, -4)
    group:SetScript("OnClick", function(btn)
        local items = { { text = "Count members by", isTitle = true } }
        for _, g in ipairs(ST.GROUPS) do
            items[#items + 1] = { text = g.label, radio = true,
                checked = function() return PV.sGroup == g.key end,
                func = function() PV.sGroup = g.key; PV:RefreshStatEditor() end }
        end
        W.ShowMenu(btn, items)
    end)
    self.sGroupBtn = group

    local fLabel = Label(c, "Filters  |cff9d9d9d(optional)|r")
    fLabel:SetPoint("TOPLEFT", 14, -134)
    self.sFilter = Input(c, IW - 8, ST.FILTER_MAX)
    self.sFilter:SetPoint("TOPLEFT", fLabel, "BOTTOMLEFT", 6, -2)
    self.sFilter:HookScript("OnTextChanged", function(_, user) if user then PV:RefreshStatEditor() end end)
    W.Tooltip(self.sFilter, "Filters", "The same words as the roster search; every one must match.",
        "class:warrior  race:orc  rank:officer  prof:tailoring  tag:raiding  level>=20  is:alt  is:main  is:addon  is:online",
        "Put a minus in front to leave members out: -is:alt")
    local add = W.Button(c, "Add Filter", 100, 20)
    add:SetPoint("TOPLEFT", self.sFilter, "BOTTOMLEFT", -6, -4)
    add:SetScript("OnClick", function(btn) PV:FilterMenu(btn) end)
    local clear = W.Button(c, "Clear", 70, 20)
    clear:SetPoint("LEFT", add, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function()
        PV.sFilter:SetText("")
        PV:RefreshStatEditor()
    end)
    self.sMatches = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.sMatches:SetPoint("LEFT", clear, "RIGHT", 10, 0)

    local vLabel = Label(c, "Who can see it")
    vLabel:SetPoint("TOPLEFT", 14, -212)
    local vis = DropButton(c, 170)
    vis:SetPoint("TOPLEFT", vLabel, "BOTTOMLEFT", 0, -4)
    vis:SetScript("OnClick", function(btn)
        local officer = ns.IsOfficer()
        local items = { { text = "Who can see it", isTitle = true } }
        for _, v in ipairs(ST.VISIBILITY) do
            items[#items + 1] = { text = v.label, radio = true,
                disabled = v.key ~= "m" and not officer,
                checked = function() return PV.sVis == v.key end,
                func = function()
                    if v.key ~= "m" and not ns.IsOfficer() then return end
                    PV.sVis = v.key
                    PV:RefreshStatEditor()
                end }
        end
        W.ShowMenu(btn, items)
    end)
    self.sVisBtn = vis
    self.sVisHint = Para(c, "GameFontDisableSmall", IW)
    self.sVisHint:SetPoint("TOPLEFT", vis, "BOTTOMLEFT", 0, -6)

    local save = W.Button(c, SAVE or "Save", 100, 22)
    save:SetPoint("BOTTOMLEFT", 12, 12)
    save:SetScript("OnClick", function() PV:SaveStat() end)
    local cancel = W.Button(c, CANCEL or "Cancel", 90, 22)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        PV.mode = nil
        PV:Refresh()
    end)
    self.sError = Para(c, "GameFontHighlightSmall", IW)
    self.sError:SetPoint("BOTTOMLEFT", save, "TOPLEFT", 2, 8)
    self.sError:SetTextColor(1, 0.35, 0.35)

    -- each row's icon and color (the rows the stat has right now)
    local rLabel = Label(c, "Rows  |cff9d9d9d(icon and color for each)|r")
    rLabel:SetPoint("TOPLEFT", self.sVisHint, "BOTTOMLEFT", 0, -12)
    local scroll = W.TryCreate("ScrollFrame", nil, c, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", rLabel, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -30, 64)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(IW - 24, 10)
    scroll:SetScrollChild(list)
    self.sRowList, self.sRowFrames = list, {}
    self.sRowsEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sRowsEmpty:SetPoint("TOPLEFT", 2, -4)
    self.sRowsEmpty:SetText("No rows yet: no members match.")

    self.sTitle.nextBox = self.sFilter
    self.sFilter.nextBox = self.sTitle

    -- on a custom stat's page: Edit and Delete
    local d = self.detailPane
    local edit = W.Button(d, "Edit Stat", 100, 22)
    edit:SetPoint("BOTTOMLEFT", 12, 12)
    edit:SetScript("OnClick", function() if PV.stat and PV.stat.custom then PV:ShowStatEditor(PV.stat.custom) end end)
    self.statEditBtn = edit
    local del = W.Button(d, DELETE or "Delete", 90, 22)
    del:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    del:SetScript("OnClick", function()
        local cst = PV.stat and PV.stat.custom
        if not cst then return end
        local who = cst.vis == "m" and "" or (cst.vis == "c" and " for everyone" or " for all officers")
        W.Confirm(("Delete the stat \"%s\"%s?"):format(cst.title, who), function()
            local ok, err = ns.Stats:Delete(cst.id)
            if not ok and err then
                ns:Print("|cffff5555" .. err .. "|r")
            else
                PV.selected = nil
                PV:Refresh()
            end
        end)
    end)
    self.statDeleteBtn = del
end

-- custom: the stat to edit, or nil for a new one.
function PV:ShowStatEditor(custom)
    if not ns.DB:Guild() then return end
    self.mode = "stat"
    self.sEditing = custom and custom.id or nil
    self.sHeader:SetText(custom and "Edit Stat" or "New Stat")
    self.sTitle:SetText(custom and custom.title or "")
    self.sFilter:SetText(custom and custom.filter or "")
    self.sGroup = custom and custom.group or "class"
    self.sVis = custom and custom.vis or (ns.IsOfficer() and "c" or "m")
    -- the chosen row looks, copied so Cancel leaves the stat as it was
    self.sLooks = {}
    for label, l in pairs(custom and custom.looks or {}) do self.sLooks[label] = { color = l.color, icon = l.icon } end
    self.sError:SetText("")
    self:Refresh()
    self.sTitle:SetFocus()
end

function PV:RefreshStatEditor()
    local ST = ns.Stats
    local g = ST:Group(self.sGroup)
    self.sGroupBtn:SetText(g and g.label or "Choose...")
    self:RefreshStatRowLooks()
    if self.sVis ~= "m" and not ns.IsOfficer() then self.sVis = "m" end
    for _, v in ipairs(ST.VISIBILITY) do
        if v.key == self.sVis then self.sVisBtn:SetText(v.label) end
    end
    self.sVisHint:SetText(self.sVis == "c" and "Shared with everyone in the guild running the addon."
        or self.sVis == "o" and "Shared with officers only. Guildmates never receive it."
        or "Kept in your copy of the addon; nobody else sees it.")
    local n, total = ST:MatchCount(self.sFilter:GetText())
    self.sMatches:SetText(("Matches %d of %d members"):format(n, total))
    self.sError:SetText("")
end

-- The form's row list: every row the stat would show now, with an icon
-- button and color swatch (its own look until you pick another).
function PV:RefreshStatRowLooks()
    local looks = self.sLooks or {}
    local rows = ns.Stats:Rows(self.sGroup, self.sFilter:GetText(), looks)
    local list, frames = self.sRowList, self.sRowFrames
    local Key = ns.Sync.Codec.LookLabel
    for i, row in ipairs(rows) do
        local f = frames[i]
        if not f then
            f = CreateFrame("Frame", nil, list)
            f:SetSize(list:GetWidth(), 24)
            f:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
            f.Controls = LookControls(f,
                function()
                    local r = f.row
                    local chosen = looks and PV.sLooks[Key(r.label)] or {}
                    return { color = chosen.color, r = r.r, g = r.g, b = r.b, icon = r.icon, classFile = r.classFile }
                end,
                function(field, value)
                    local key = Key(f.row.label)
                    PV.sLooks[key] = PV.sLooks[key] or {}
                    PV.sLooks[key][field] = value
                    PV:RefreshStatRowLooks()
                end)
            f.Controls:SetPoint("LEFT", 2, 0)
            f.Label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.Label:SetPoint("LEFT", 54, 0)
            f.Label:SetPoint("RIGHT", -50, 0)
            f.Label:SetJustifyH("LEFT")
            f.Label:SetWordWrap(false)
            f.Count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            f.Count:SetPoint("RIGHT", -4, 0)
            frames[i] = f
        end
        f.row = row
        f.Label:SetText(row.label)
        f.Label:SetTextColor(row.r or 1, row.g or 1, row.b or 1)
        f.Count:SetText(row.count)
        f.Controls:Refresh()
        f:Show()
    end
    for i = #rows + 1, #frames do frames[i]:Hide() end
    self.sRowsEmpty:SetShown(#rows == 0)
    list:SetHeight(math.max(10, #rows * 24))
end

function PV:SaveStat()
    local id, err = ns.Stats:Save(self.sEditing, self.sTitle:GetText(), self.sGroup, self.sFilter:GetText(), self.sVis,
        self.sLooks)
    if not id then
        self.sError:SetText(err or "Couldn't save the stat.")
        return
    end
    self.sTitle:ClearFocus()
    self.sFilter:ClearFocus()
    self:Select(STAT_PREFIX .. id)
end

function PV:BuildCreate(panel)
    local P = ns.Polls
    local c = CreateFrame("Frame", nil, panel)
    c:SetAllPoints()
    c:Hide()
    self.createPane = c

    local title, line = W.SectionHeader(c, "New Poll")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", c, "RIGHT", -12, 0)

    local qLabel = Label(c, "Question")
    qLabel:SetPoint("TOPLEFT", 14, -36)
    self.qBox = Input(c, IW - 8, P.QUESTION_MAX)
    self.qBox:SetPoint("TOPLEFT", qLabel, "BOTTOMLEFT", 6, -2)

    local aLabel = Label(c, ("Answers  |cff9d9d9d(%d to %d)|r"):format(P.MIN_OPTIONS, P.MAX_OPTIONS))
    aLabel:SetPoint("TOPLEFT", 14, -82)
    self.optBoxes, self.optLookControls = {}, {}
    local prev = self.qBox
    for i = 1, P.MAX_OPTIONS do
        local num = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        num:SetPoint("TOPLEFT", 16, -102 - (i - 1) * 24)
        num:SetText(i .. ".")
        -- the answer's icon and color
        local looks = LookControls(c,
            function() return PV.answerLooks and PV.answerLooks[i] or {} end,
            function(field, value)
                PV.answerLooks[i][field] = value or nil
                PV.optLookControls[i]:Refresh()
            end)
        looks:SetPoint("LEFT", num, "LEFT", 16, 0)
        self.optLookControls[i] = looks
        local eb = Input(c, IW - 76, P.OPTION_MAX)
        eb:SetPoint("LEFT", looks, "RIGHT", 10, 0)
        prev.nextBox = eb
        prev = eb
        self.optBoxes[i] = eb
    end

    local y = -102 - P.MAX_OPTIONS * 24 - 8
    local closeLabel = Label(c, "Voting closes in")
    closeLabel:SetPoint("TOPLEFT", 14, y - 4)
    self.closeNum = Input(c, 44, 4, true)
    self.closeNum:SetPoint("TOPLEFT", 150, y)
    prev.nextBox = self.closeNum
    local unit = W.Button(c, "", 96, 22)
    unit:SetPoint("LEFT", self.closeNum, "RIGHT", 6, 0)
    unit:SetScript("OnClick", function(self)
        local items = { { text = "Voting closes in", isTitle = true } }
        for _, u in ipairs(P.UNITS) do
            items[#items + 1] = {
                text = u.label, radio = true,
                checked = function() return PV.unit == u.key end,
                func = function()
                    PV.unit = u.key
                    PV:RefreshCreate()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    self.unitBtn = unit

    y = y - 30
    local keepLabel = Label(c, "Keep results after closing")
    keepLabel:SetPoint("TOPLEFT", 14, y - 4)
    keepLabel:SetWidth(132)
    keepLabel:SetJustifyH("LEFT")
    self.keepNum = Input(c, 44, 3, true)
    self.keepNum:SetPoint("TOPLEFT", 150, y)
    self.closeNum.nextBox = self.keepNum
    self.keepNum.nextBox = self.qBox
    local days = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    days:SetPoint("LEFT", self.keepNum, "RIGHT", 8, 0)
    days:SetText("days")

    self.closeHint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.closeHint:SetPoint("TOPLEFT", 14, y - 26)
    self.closeHint:SetPoint("RIGHT", -14, 0)
    self.closeHint:SetJustifyH("LEFT")
    self.closeNum:HookScript("OnTextChanged", function() PV:RefreshCreate() end)
    self.keepNum:HookScript("OnTextChanged", function() PV:RefreshCreate() end)

    local create = W.Button(c, "Create Poll", 120, 22)
    create:SetPoint("BOTTOMLEFT", 12, 12)
    create:SetScript("OnClick", function() PV:OnCreate() end)
    local cancel = W.Button(c, CANCEL or "Cancel", 90, 22)
    cancel:SetPoint("LEFT", create, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        PV.mode = nil
        PV:Refresh()
    end)

    self.createError = Para(c, "GameFontHighlightSmall", IW)
    self.createError:SetPoint("BOTTOMLEFT", create, "TOPLEFT", 2, 8)
    self.createError:SetTextColor(1, 0.35, 0.35)
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
function PV:Select(id)
    self.selected = id
    self.mode = "detail"
    self:Refresh()
end

function PV:ShowCreate()
    if not ns.Polls:CanCreate() then return end
    local P = ns.Polls
    self.mode = "create"
    self.unit = P.DEFAULT_CLOSE[2]
    -- each answer starts in its own color, with no icon
    self.answerLooks = {}
    for i = 1, P.MAX_OPTIONS do self.answerLooks[i] = { color = P.AnswerColor(i) } end
    self.qBox:SetText("")
    for _, eb in ipairs(self.optBoxes) do eb:SetText("") end
    self.closeNum:SetText(tostring(P.DEFAULT_CLOSE[1]))
    self.keepNum:SetText(tostring(P.DEFAULT_KEEP_DAYS))
    self.createError:SetText("")
    self:Refresh()
    self.qBox:SetFocus()
end

function PV:CloseSeconds()
    local n = tonumber(self.closeNum:GetText())
    local secs = ns.Polls.UnitSeconds(self.unit)
    return n and secs and n * secs
end

function PV:RefreshCreate()
    self.unitBtn:SetText(ns.Polls.UnitLabel(self.unit) or "Days")
    for _, controls in ipairs(self.optLookControls) do controls:Refresh() end
    local secs = self:CloseSeconds()
    local keep = tonumber(self.keepNum:GetText())
    if secs and secs >= 60 then
        local closeAt = time() + secs
        local hint = "Closes " .. ns.FormatDate(closeAt)
        if keep then hint = hint .. (keep == 1 and ", results kept 1 day after." or (", results kept %d days after."):format(keep)) end
        self.closeHint:SetText(hint)
    else
        self.closeHint:SetText("")
    end
end

function PV:OnCreate()
    local options = {}
    for i, eb in ipairs(self.optBoxes) do options[i] = eb:GetText() end
    local id, err = ns.Polls:Create(self.qBox:GetText(), options, self:CloseSeconds(), self.keepNum:GetText(), self.answerLooks)
    if not id then
        self.createError:SetText(err or "Couldn't create the poll.")
        return
    end
    for _, eb in ipairs(self.optBoxes) do eb:ClearFocus() end
    self.qBox:ClearFocus()
    ns:Print(("Poll created. Guildmates running the addon can vote on the %s tab."):format(ns.TabName("polls")))
    self:Select(id)
end

function PV:OnVote(index)
    local p = self.current
    if not p or not p.open then return end
    local ok, err = ns.Polls:Vote(p.id, index)
    if not ok and err then
        ns:Print("|cffff5555" .. err .. "|r")
    else
        ns.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:Refresh()
    end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
-- Opening a poll or stat (or the tab), the bars grow and the pie sweeps in
-- clockwise over ANIM_TIME, fast at first and easing to a stop. Live
-- updates of what's already shown just change the values.
local ANIM_TIME = 0.4
PV.barTargets = {}

function PV:AnimStep(t)
    local e = 1 - (1 - t) ^ 3
    for bar, target in pairs(self.barTargets) do bar:SetValue(target * e) end
    self.pie:SetProgress(e)
end

function PV:StartAnimation()
    self.animStart = GetTime()
    self.animating = true
    local driver = self.animDriver or CreateFrame("Frame")
    self.animDriver = driver
    self:AnimStep(0)
    driver:SetScript("OnUpdate", function()
        local t = (GetTime() - PV.animStart) / ANIM_TIME
        if t >= 1 then
            driver:SetScript("OnUpdate", nil)
            PV.animating = false
            PV:AnimStep(1)
        else
            PV:AnimStep(t)
        end
    end)
end

-- Rows stretch across the panel; the pie sits under them (and the footer
-- text), centered, as big as the room left allows.
local function PlaceRow(r, prev, gap, d)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, gap)
    r:SetPoint("RIGHT", d, "RIGHT", -14, 0)
end

local function PlaceFooter(self, prev)
    self.dFooter:ClearAllPoints()
    self.dFooter:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
    self.dFooter:SetPoint("RIGHT", self.detailPane, "RIGHT", -14, 0)
end

-- rowsHeight: the height of the result rows shown. Call after the footer's text is set.
local function PlacePie(self, rowsHeight)
    local d, pie = self.detailPane, self.pie
    local paneH = d:GetHeight()
    if not paneH or paneH < 50 then paneH = 420 end
    local used = 12 + 18 + 10 + (self.dQuestion:GetStringHeight() or 16) + 6 + (self.dStatus:GetStringHeight() or 12)
        + 12 + rowsHeight + 10 + (self.dFooter:GetStringHeight() or 0)
    local room = paneH - used - 14 - 44 -- gap above the pie, the buttons along the bottom
    local size = math.floor(math.min(PIE_MAX, room))
    pie:ClearAllPoints()
    if size < PIE_MIN then
        pie:Hide() -- no room (lots of rows); the bars say it all
        return
    end
    pie:SetSize(size, size)
    -- the footer spans the panel, so this centers the pie under it
    pie:SetPoint("TOP", self.dFooter, "BOTTOM", 0, -14)
    pie:Show()
end

function PV:RefreshDetail(p)
    self.current, self.stat = p, nil
    for _, r in ipairs(self.statRows) do r:Hide() end
    self.statEditBtn:Hide()
    self.statDeleteBtn:Hide()
    self.dTitle:SetText("Poll")
    self.dQuestion:SetText(p.question)
    self.dStatus:SetText(StatusText(p) .. "  -  " .. VotesText(p.total))

    local most = 0
    for _, n in ipairs(p.counts) do most = math.max(most, n) end
    local d, prev, gap = self.detailPane, self.dStatus, -12
    local slices, rowsHeight = {}, 0
    for i, r in ipairs(self.optionRows) do
        local text = p.options[i]
        if text then
            local n = p.counts[i]
            local pct = p.total > 0 and math.floor(n * 100 / p.total + 0.5) or 0
            -- the answer's own color and icon
            local look = p.answerLooks and p.answerLooks[i] or {}
            local cr, cg, cb = D:TagColor(look.color or ns.Polls.AnswerColor(i))
            slices[i] = { n, cr, cg, cb }
            local hasIcon = SetRowIcon(r.Icon, look)
            r.Text:SetPoint("TOPLEFT", hasIcon and 38 or 20, -3)
            r.Text:SetText(text)
            -- the leading answer's count turns gold once voting closed
            local lead = not p.open and n > 0 and n == most
            r.Count:SetText(("%s%d|r  |cff9d9d9d%d%%|r"):format(lead and "|cffffd100" or "|cffffffff", n, pct))
            self.barTargets[r.Bar] = p.total > 0 and n / p.total or 0
            r.Bar:SetValue(self.barTargets[r.Bar])
            r.Bar:SetStatusBarColor(cr, cg, cb)
            r.Check:SetShown(p.myVote == i)
            if p.myVote == i then r.Text:SetTextColor(0.4, 1, 0.4) else r.Text:SetTextColor(1, 1, 1) end
            PlaceRow(r, prev, gap, d)
            r:Show()
            rowsHeight = rowsHeight + r:GetHeight() + (prev == self.dStatus and 0 or 4)
            prev, gap = r, -4
        else
            r:Hide()
        end
    end
    self.pie:SetSlices(slices)

    PlaceFooter(self, prev)
    if p.open then
        self.dFooter:SetText(p.myVote and "You can change your vote until the poll closes."
            or "Click an answer to vote. You can change your vote until the poll closes.")
    else
        self.dFooter:SetText("Voting has closed. Only votes cast before it closed are counted.")
    end
    PlacePie(self, rowsHeight)

    local officer = ns.IsOfficer()
    self.closeBtn:SetShown(officer and p.open)
    self.deleteBtn:SetShown(officer)
    self.deleteBtn:ClearAllPoints()
    if self.closeBtn:IsShown() then
        self.deleteBtn:SetPoint("LEFT", self.closeBtn, "RIGHT", 8, 0)
    else
        self.deleteBtn:SetPoint("BOTTOMLEFT", 12, 12)
    end
end

-- A guild stat, shown like a closed poll: rows with bars and the pie.
function PV:RefreshStat(id)
    local s = ns.Stats:Compute(id)
    self.current, self.stat = nil, s
    for _, r in ipairs(self.optionRows) do r:Hide() end
    self.closeBtn:Hide()
    self.deleteBtn:Hide()
    local editable = s.custom and ns.Stats:CanEdit(s.custom) or false
    self.statEditBtn:SetShown(editable)
    self.statDeleteBtn:SetShown(editable)
    local vis = s.custom and s.custom.vis
    self.dTitle:SetText(vis == "o" and "Officer Stat" or vis == "m" and "My Stat" or "Guild Stat")
    self.dQuestion:SetText(s.title)
    self.dStatus:SetText("|cff66bbff" .. s.sub .. "|r")

    local d, prev, gap = self.detailPane, self.dStatus, -12
    local slices, rowsHeight = {}, 0
    for i, r in ipairs(self.statRows) do
        local row = s.rows[i]
        if row then
            local pct = s.total > 0 and math.floor(row.count * 100 / s.total + 0.5) or 0
            slices[i] = { row.count, row.r, row.g, row.b }
            r.Label:SetPoint("TOPLEFT", SetRowIcon(r.Icon, row) and 20 or 2, -2)
            r.Label:SetText(row.label)
            r.Label:SetTextColor(row.r, row.g, row.b)
            r.Count:SetText(("%d  |cff9d9d9d%d%%|r"):format(row.count, pct))
            self.barTargets[r.Bar] = s.total > 0 and row.count / s.total or 0
            r.Bar:SetValue(self.barTargets[r.Bar])
            r.Bar:SetStatusBarColor(row.r, row.g, row.b)
            PlaceRow(r, prev, gap, d)
            r:Show()
            rowsHeight = rowsHeight + r:GetHeight() + (prev == self.dStatus and 0 or 4)
            prev, gap = r, -4
        else
            r:Hide()
        end
    end
    self.pie:SetSlices(slices)

    PlaceFooter(self, prev)
    local foot = {}
    if #s.rows == 0 then foot[#foot + 1] = "Nothing to show yet." end
    if #s.rows > MAX_STAT_ROWS then foot[#foot + 1] = ("Showing the top %d."):format(MAX_STAT_ROWS) end
    if s.note then foot[#foot + 1] = s.note end
    for _, row in ipairs(s.rows) do
        if row.query then
            foot[#foot + 1] = "Click a row or slice to see those members in the roster."
            break
        end
    end
    self.dFooter:SetText(table.concat(foot, "\n"))
    PlacePie(self, rowsHeight)
end

-- The list: open polls, guild stats, closed polls.
local function ListItems(polls)
    local items, open, closed = {}, {}, {}
    for _, p in ipairs(polls) do
        if p.open then open[#open + 1] = p else closed[#closed + 1] = p end
    end
    local function Section(title, list, wrap)
        if #list == 0 then return end
        items[#items + 1] = { header = title }
        for i, x in ipairs(list) do
            local item = wrap(x)
            item.stripe = i % 2 == 0
            items[#items + 1] = item
        end
    end
    -- stats in a section for who sees them: Guild Stats, Officers, My Stats
    local byVis = {}
    for _, c in ipairs(ns.Stats:All()) do
        byVis[c.vis] = byVis[c.vis] or {}
        table.insert(byVis[c.vis], { id = c.id, name = c.title })
    end
    -- goals first, with how far along they are
    local goals = {}
    for _, g in ipairs(ns.Goals:All()) do
        local pct, done = ns.Goals:Percent(g.id)
        goals[#goals + 1] = { key = GOAL_PREFIX .. g.id, name = g.title,
            right = done and "|cff40ff40done|r" or (pct .. "%") }
    end
    Section("Goals", goals, function(s) return { stat = s } end)
    Section("Open Polls", open, function(p) return { poll = p } end)
    for _, v in ipairs(ns.Stats.VISIBILITY) do
        Section(v.section, byVis[v.key] or {}, function(s) return { stat = s } end)
    end
    Section("Closed Polls", closed, function(p) return { poll = p } end)
    return items
end

function PV:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    local officer = ns.IsOfficer()
    local inGuild = IsInGuild() and ns.DB:Guild() ~= nil
    local list = inGuild and ns.Polls:List() or {}
    local open = 0
    for _, p in ipairs(list) do if p.open then open = open + 1 end end
    self.summary:SetText("Guild Polls")
    self.sub:SetText(#list == 0 and "" or (open == 1 and "1 open" or (open .. " open")) .. (#list > open and ("  -  " .. (#list - open) .. " closed") or ""))
    self.newBtn:SetShown(officer)
    self.newStatBtn:SetShown(inGuild)
    self.newGoalBtn:SetShown(inGuild)
    if self.mode == "create" and not officer then self.mode = nil end
    local editing = self.mode == "create" or self.mode == "stat" or self.mode == "goalForm"

    -- keep the selection; else an open poll you haven't voted on, any open
    -- poll, or the first stat
    local statId, goalId = StatId(self.selected), GoalId(self.selected)
    if statId and not ns.Stats:Name(statId) then statId, self.selected = nil, nil end -- deleted
    if goalId and not ns.Goals:Get(goalId) then goalId, self.selected = nil, nil end
    local current = not statId and not goalId and self.selected and ns.Polls:Get(self.selected)
    if not editing and inGuild and not current and not statId and not goalId then
        for _, p in ipairs(list) do
            if p.open and not p.myVote then current = p break end
        end
        if not current and list[1] and list[1].open then current = list[1] end
        local first = ns.Stats:All()[1]
        if current then
            self.selected = current.id
        elseif first then
            statId = first.id
            self.selected = STAT_PREFIX .. statId
        end
    end
    if not editing or not inGuild then
        -- nothing at all to show (no polls, every stat deleted): the info pane
        self.mode = (inGuild and (current or statId or goalId)) and "detail" or nil
    end

    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(inGuild and ListItems(list) or {}), retain)

    local GV = ns.GoalsView
    self.createPane:SetShown(self.mode == "create")
    self.statPane:SetShown(self.mode == "stat")
    GV.form:SetShown(self.mode == "goalForm")
    self.detailPane:SetShown(self.mode == "detail" and not goalId)
    GV.page:SetShown(self.mode == "detail" and goalId ~= nil)
    self.infoPane:SetShown(self.mode == nil)
    if self.mode == "create" then
        self.current, self.stat = nil, nil
        self:RefreshCreate()
    elseif self.mode == "stat" then
        self.current, self.stat = nil, nil
        self:RefreshStatEditor()
    elseif self.mode == "goalForm" then
        self.current, self.stat = nil, nil
        GV:RefreshEditor()
    elseif self.mode == "detail" then
        wipe(self.barTargets)
        if goalId then
            self.current, self.stat = nil, nil
            GV:ShowGoal(goalId)
        elseif statId then
            self:RefreshStat(statId)
        else
            self:RefreshDetail(current)
        end
        -- grow in when something new is shown; live updates just change
        local key = goalId and (GOAL_PREFIX .. goalId) or statId and (STAT_PREFIX .. statId) or current.id
        local animate = self.animateNext or key ~= self.shownKey
        self.shownKey, self.animateNext = key, false
        if animate then
            self:StartAnimation()
        elseif self.animating then
            self:AnimStep(math.min(1, (GetTime() - self.animStart) / ANIM_TIME))
        else
            self.pie:SetProgress(1)
        end
    else
        self.current, self.stat = nil, nil
        self.infoText:SetText(inGuild and "No polls or stats yet. Click New Stat to count guildmates your way."
            or "Join a guild to see its polls and stats.")
    end
end


