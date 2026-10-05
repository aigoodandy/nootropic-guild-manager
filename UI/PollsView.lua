--[[
    Nootropic Guild Manager - Polls tab
    Everyone: see the guild's polls, vote (and change your vote) until a poll
    closes, and see the results, also after it closes.
    Officers: create polls, close voting early, delete polls.
]]
local _, ns = ...
local W = ns.Widgets
local PV = {}
ns.PollsView = PV

local ROW_H = 46
local PANEL_W = 340
local IW = PANEL_W - 28
local OPTION_H = 38

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
    page:SetScript("OnShow", function() PV:Refresh() end)

    self.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 84, -38)
    self.sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sub:SetPoint("LEFT", self.summary, "RIGHT", 14, 0)

    local new = W.Button(page, "New Poll", 100, 22)
    new:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    new:SetScript("OnClick", function() PV:ShowCreate() end)
    W.Tooltip(new, "New poll", "Ask the guild a question with 2 to 6 answers.", "Officers only.")
    self.newBtn = new

    local inset = frame.Inset
    self:BuildList(page, inset)
    self:BuildPanel(page, inset)

    local function changed()
        if page:IsVisible() then ns.Debounce("pollsview", 0.1, function() PV:Refresh() end) end
    end
    ns:On("POLLS_CHANGED", changed)
    ns:On("POLLS_TICK", changed)
    ns:On("OFFICER_CHANGED", changed)
end

function PV:BuildList(page, inset)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -(PANEL_W + 14), 4)

    local scrollBox = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
    local scrollBar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, p) PV:InitRow(row, p) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.emptyText = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.emptyText:SetPoint("CENTER", 0, 20)
    self.emptyText:SetWidth(360)
end

function PV:InitRow(row, p)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
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
        row.Question = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.Question:SetPoint("TOPLEFT", 10, -7)
        row.Question:SetPoint("RIGHT", -90, 0)
        row.Question:SetJustifyH("LEFT")
        row.Question:SetWordWrap(false)
        row.Votes = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Votes:SetPoint("TOPRIGHT", -10, -8)
        row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Status:SetPoint("TOPLEFT", row.Question, "BOTTOMLEFT", 0, -5)
        row.Mine = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.Mine:SetPoint("TOPRIGHT", row.Votes, "BOTTOMRIGHT", 0, -5)
        row:SetScript("OnClick", function(self) if self.poll then PV:Select(self.poll.id) end end)
    end
    row.poll = p
    row.Stripe:SetShown(p._stripe)
    row.Selected:SetShown(p.id == self.selected and self.mode == "detail")
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

------------------------------------------------------------------------
-- Right panel
------------------------------------------------------------------------
function PV:BuildPanel(page, inset)
    local panel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    panel:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -6, -4)
    panel:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
    panel:SetWidth(PANEL_W)
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
end

function PV:BuildDetail(panel)
    local d = CreateFrame("Frame", nil, panel)
    d:SetAllPoints()
    d:Hide()
    self.detailPane = d

    local title, line = W.SectionHeader(d, "Poll")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    self.dQuestion = Para(d, "GameFontHighlight", IW)
    self.dQuestion:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    self.dStatus = Para(d, "GameFontHighlightSmall", IW)
    self.dStatus:SetPoint("TOPLEFT", self.dQuestion, "BOTTOMLEFT", 0, -6)

    self.optionRows = {}
    for i = 1, ns.Polls.MAX_OPTIONS do
        local r = CreateFrame("Button", nil, d)
        r:SetSize(IW, OPTION_H - 4)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:GetHighlightTexture():SetAlpha(0.3)
        r.Check = r:CreateTexture(nil, "OVERLAY")
        r.Check:SetSize(14, 14)
        r.Check:SetPoint("TOPLEFT", 2, -2)
        r.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
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
        r:SetScript("OnEnter", function(self)
            local p = PV.current
            if not p then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(p.options[self.index] or "", 1, 1, 1, true)
            if p.open then
                GameTooltip:AddLine(p.myVote == self.index and "Your vote." or "Click to vote for this answer.", 0.6, 0.85, 1, true)
                if p.myVote and p.myVote ~= self.index then
                    GameTooltip:AddLine("You can change your vote until the poll closes.", 0.7, 0.7, 0.7, true)
                end
            else
                GameTooltip:AddLine("Voting has closed.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.index = i
        self.optionRows[i] = r
    end

    self.dFooter = Para(d, "GameFontDisableSmall", IW)

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
    self.optBoxes = {}
    local prev = self.qBox
    for i = 1, P.MAX_OPTIONS do
        local num = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        num:SetPoint("TOPLEFT", 16, -102 - (i - 1) * 24)
        num:SetText(i .. ".")
        local eb = Input(c, IW - 28, P.OPTION_MAX)
        eb:SetPoint("LEFT", num, "LEFT", 18, 0)
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
    local id, err = ns.Polls:Create(self.qBox:GetText(), options, self:CloseSeconds(), self.keepNum:GetText())
    if not id then
        self.createError:SetText(err or "Couldn't create the poll.")
        return
    end
    for _, eb in ipairs(self.optBoxes) do eb:ClearFocus() end
    self.qBox:ClearFocus()
    ns:Print("Poll created. Guildmates running the addon can vote on the Polls tab.")
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
function PV:RefreshDetail(p)
    self.current = p
    self.dQuestion:SetText(p.question)
    self.dStatus:SetText(StatusText(p) .. "  -  " .. VotesText(p.total))

    local most = 0
    for _, n in ipairs(p.counts) do most = math.max(most, n) end
    local prev, gap = self.dStatus, -12
    for i, r in ipairs(self.optionRows) do
        local text = p.options[i]
        if text then
            local n = p.counts[i]
            local pct = p.total > 0 and math.floor(n * 100 / p.total + 0.5) or 0
            r.Text:SetText(text)
            r.Count:SetText(("%d  |cff9d9d9d%d%%|r"):format(n, pct))
            r.Bar:SetValue(p.total > 0 and n / p.total or 0)
            -- the leading answer is gold once voting closed, otherwise blue
            if not p.open and n > 0 and n == most then
                r.Bar:SetStatusBarColor(1, 0.75, 0.1)
            else
                r.Bar:SetStatusBarColor(0.15, 0.45, 0.9)
            end
            r.Check:SetShown(p.myVote == i)
            if p.myVote == i then r.Text:SetTextColor(0.4, 1, 0.4) else r.Text:SetTextColor(1, 1, 1) end
            r:SetEnabled(p.open)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, gap)
            r:Show()
            prev, gap = r, -4
        else
            r:Hide()
        end
    end

    self.dFooter:ClearAllPoints()
    self.dFooter:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12)
    if p.open then
        self.dFooter:SetText(p.myVote and "You can change your vote until the poll closes."
            or "Click an answer to vote. You can change your vote until the poll closes.")
    else
        self.dFooter:SetText("Voting has closed. Only votes cast before it closed are counted.")
    end

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

function PV:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    local officer = ns.IsOfficer()
    local list = ns.Polls:List()
    local open = 0
    for i, p in ipairs(list) do
        p._stripe = (i % 2 == 0)
        if p.open then open = open + 1 end
    end
    self.summary:SetText("Guild Polls")
    self.sub:SetText(#list == 0 and "" or (open == 1 and "1 open" or (open .. " open")) .. (#list > open and ("  -  " .. (#list - open) .. " closed") or ""))
    self.newBtn:SetShown(officer)
    if self.mode == "create" and not officer then self.mode = nil end

    -- pick the first poll when nothing is chosen
    local current = self.selected and ns.Polls:Get(self.selected)
    if self.mode ~= "create" then
        if not current and #list > 0 then
            current = list[1]
            self.selected = current.id
        end
        self.mode = current and "detail" or nil
    end

    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    if not IsInGuild() or not ns.DB:Guild() then
        self.emptyText:SetText("Join a guild to see its polls.")
    elseif #list == 0 then
        self.emptyText:SetText(officer and "No polls yet. Click New Poll to ask the guild something."
            or "No polls yet. Officers can create polls; you'll be able to vote on them here.")
    else
        self.emptyText:SetText("")
    end

    self.createPane:SetShown(self.mode == "create")
    self.detailPane:SetShown(self.mode == "detail")
    self.infoPane:SetShown(self.mode == nil)
    if self.mode == "create" then
        self:RefreshCreate()
    elseif self.mode == "detail" then
        self:RefreshDetail(current)
    else
        self.current = nil
        self.infoText:SetText(officer
            and "Ask the guild a question: click |cffffd100New Poll|r, write 2 to 6 answers and choose when voting closes (1 week unless you change it).\n\nEveryone running the addon can vote and change their vote until the poll closes. Results stay visible after closing for the number of days you choose (7 by default)."
            or "Officers post polls here. Pick an answer to vote; you can change your vote until the poll closes.\n\nResults stay visible for a while after voting closes.")
    end
end
