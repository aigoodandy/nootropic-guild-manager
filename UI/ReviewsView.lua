--[[
    Nootropic Guild Manager - Reviews tab (last tab)
    Everyone: write an anonymous review of the guild (1-5 stars and a
    message), once every 7 days.
    Officers: read every review from the last year (newest first), see the
    average, and leave comments other officers can read.
]]
local _, ns = ...
local W = ns.Widgets
local RW = {}
ns.ReviewsView = RW

local ROW_H = 58
local PANEL_W = 330

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "NootropicGM_GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function Para(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "NootropicGM_GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(width)
    fs:SetSpacing(2)
    return fs
end

local function DayText(t) return date("!%b %d, %Y", t) end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function RW:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame
    page:SetScript("OnShow", function() RW:Refresh() end)

    -- Summary across the top (officers)
    self.avgStars = W.Stars(page, 16, false)
    self.avgStars:SetPoint("TOPLEFT", frame, "TOPLEFT", 84, -38)
    self.summary = page:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
    self.summary:SetPoint("LEFT", self.avgStars, "RIGHT", 10, 0)
    self.breakdown = page:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.breakdown:SetPoint("LEFT", self.summary, "RIGHT", 14, 0)

    -- Officers: turn reviews on or off for the whole guild
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    end
    label:SetFontObject("NootropicGM_GameFontHighlightSmall")
    label:ClearAllPoints()
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText("Guildmates can review the guild")
    cb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(math.ceil(label:GetStringWidth()) + 18), -34)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        local ok, err = ns.DB:SetReviewsEnabled(on)
        if not ok and err then
            ns:Print("|cffff5555" .. err .. "|r")
        else
            ns:Print(on and "Guild reviews are on: guildmates see the Review Guild tab."
                or "Guild reviews are off: guildmates no longer see the Review Guild tab.")
        end
        RW:Refresh()
    end)
    W.Tooltip(cb, "Guild reviews", "When off, guildmates don't see the Review Guild tab and can't write reviews.",
        "Officers still see every review. Reviews are kept for a year.")
    self.enableCheck = cb

    local inset = frame.Inset
    self:BuildList(page, inset)
    self:BuildPanel(page, inset)

    ns:On("REVIEWS_CHANGED", function()
        if page:IsVisible() then ns.Debounce("reviewsview", 0.1, function() RW:Refresh() end) end
    end)
    ns:On("OFFICER_CHANGED", function() if page:IsVisible() then RW:Refresh() end end)
    ns:On("GUILD_SETTINGS_CHANGED", function() if page:IsVisible() then RW:Refresh() end end)
end

function RW:BuildList(page, inset)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -(PANEL_W + 14), 4)
    self.listBox = box

    local scrollBox = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
    local scrollBar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, r) RW:InitRow(row, r) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox, self.scrollBar = scrollBox, scrollBar

    self.emptyText = box:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisable")
    self.emptyText:SetPoint("CENTER", 0, 20)
    self.emptyText:SetWidth(380)
end

function RW:InitRow(row, r)
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
        row.Stars = W.Stars(row, 12, false)
        row.Stars:SetPoint("TOPLEFT", 8, -6)
        row.Date = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
        row.Date:SetPoint("LEFT", row.Stars, "RIGHT", 10, 0)
        row.Comments = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalSmall")
        row.Comments:SetPoint("TOPRIGHT", -8, -6)
        row.Text = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
        row.Text:SetPoint("TOPLEFT", 8, -24)
        row.Text:SetPoint("RIGHT", -8, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetJustifyV("TOP")
        row.Text:SetHeight(28)
        row.Text:SetWordWrap(true)
        if row.Text.SetMaxLines then row.Text:SetMaxLines(2) end
        row:SetScript("OnClick", function(self) if self.review then RW:Select(self.review.id) end end)
    end
    row.review = r
    row.Stripe:SetShown(r._stripe)
    row.Selected:SetShown(r.id == self.selected)
    row.Stars:SetValue(r.stars)
    row.Date:SetText(DayText(r.day))
    local n = #r.comments
    row.Comments:SetText(n == 0 and "" or (n == 1 and "1 comment" or (n .. " comments")))
    row.Text:SetText(r.text)
end

------------------------------------------------------------------------
-- Right panel: write a review / read one
------------------------------------------------------------------------
local function PanelBox(page, inset)
    local p = CreateFrame("Frame", nil, page, "BackdropTemplate")
    p:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -6, -4)
    p:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
    p:SetWidth(PANEL_W)
    p:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0, 0, 0, 0.35)
    p:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    return p
end

function RW:BuildPanel(page, inset)
    local IW = PANEL_W - 28
    self.panel = PanelBox(page, inset)

    -- Write -------------------------------------------------------------
    local w = CreateFrame("Frame", nil, self.panel)
    w:SetAllPoints()
    self.writePane = w

    local title, line = W.SectionHeader(w, "Review the Guild")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", w, "RIGHT", -12, 0)

    self.intro = Para(w, "NootropicGM_GameFontHighlightSmall", IW)
    self.intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    self.intro:SetText("Tell the officers how the guild is doing. |cff40ff40Your review is anonymous|r: your name is never saved with it or shown to anyone, and it's dated by day only.")

    local rateLabel = Label(w, "Your rating")
    rateLabel:SetPoint("TOPLEFT", self.intro, "BOTTOMLEFT", 0, -12)
    self.rateStars = W.Stars(w, 22, true, function() RW:RefreshWrite() end)
    self.rateStars:SetPoint("TOPLEFT", rateLabel, "BOTTOMLEFT", 0, -6)

    local msgLabel = Label(w, "Your message")
    msgLabel:SetPoint("TOPLEFT", self.rateStars, "BOTTOMLEFT", 0, -12)
    self.count = w:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.count:SetPoint("RIGHT", w, "RIGHT", -14, 0)
    self.count:SetPoint("TOP", msgLabel, "TOP", 0, 0)
    local ef, box = W.ScrollEditor(w, ns.Reviews.TEXT_MAX)
    ef:SetPoint("TOPLEFT", msgLabel, "BOTTOMLEFT", 2, -6)
    ef:SetSize(IW - 4, 110)
    box:SetFontObject("NootropicGM_GameFontHighlightSmall")
    box:SetWidth(IW - 22)
    box:HookScript("OnTextChanged", function() RW:RefreshWrite() end)
    self.textBox = box

    local submit = W.Button(w, "Submit Review", 130, 24)
    submit:SetPoint("TOPLEFT", ef, "BOTTOMLEFT", -2, -10)
    submit:SetScript("OnClick", function() RW:OnSubmit() end)
    self.submitBtn = submit

    self.writeStatus = Para(w, "NootropicGM_GameFontHighlightSmall", IW)
    self.writeStatus:SetPoint("TOPLEFT", submit, "BOTTOMLEFT", 2, -10)

    self.rules = Para(w, "NootropicGM_GameFontDisableSmall", IW)
    self.rules:SetPoint("TOPLEFT", self.writeStatus, "BOTTOMLEFT", 0, -12)
    self.rules:SetText("Only officers can read reviews. They can comment on them, but nobody can change or delete a review. Reviews are kept for a year. You can write one review every 7 days.")

    -- Read (officers) -----------------------------------------------------
    local d = CreateFrame("Frame", nil, self.panel)
    d:SetAllPoints()
    d:Hide()
    self.detailPane = d

    local dtitle, dline = W.SectionHeader(d, "Review")
    dtitle:SetPoint("TOPLEFT", 14, -12)
    dline:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    local back = W.Button(d, "Write a Review", 120, 20)
    back:SetPoint("TOPRIGHT", -12, -8)
    back:SetFrameLevel(d:GetFrameLevel() + 5)
    back:SetScript("OnClick", function() RW:Select(nil) end)
    self.backBtn = back

    self.detailStars = W.Stars(d, 16, false)
    self.detailStars:SetPoint("TOPLEFT", dtitle, "BOTTOMLEFT", 0, -10)
    self.detailDate = d:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    self.detailDate:SetPoint("LEFT", self.detailStars, "RIGHT", 10, 0)

    -- the review text and comments scroll
    local scroll = W.TryCreate("ScrollFrame", nil, d, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", self.detailStars, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -28, 44)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(IW - 18, 200)
    scroll:SetScrollChild(content)
    self.detailScroll, self.detailContent = scroll, content

    self.detailText = Para(content, "NootropicGM_GameFontHighlight", IW - 22)
    self.detailText:SetPoint("TOPLEFT", 0, 0)
    self.commentsTitle = Label(content, "Officer comments")
    self.commentsTitle:SetPoint("TOPLEFT", self.detailText, "BOTTOMLEFT", 0, -14)
    self.commentRows = {}

    local input = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    input:SetSize(IW - 66, 20)
    input:SetPoint("BOTTOMLEFT", 20, 14)
    input:SetAutoFocus(false)
    input:SetFontObject("NootropicGM_GameFontHighlightSmall")
    input:SetMaxLetters(ns.Reviews.COMMENT_MAX)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function() RW:OnAddComment() end)
    if type(input.Instructions) == "table" then input.Instructions:SetText("Add a comment for officers...") end
    self.commentBox = input
    local add = W.Button(d, "Add", 54, 22)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    add:SetScript("OnClick", function() RW:OnAddComment() end)
    W.Tooltip(add, "Add comment", "Other officers can read it. Only you can delete your own comment.")
    self.addCommentBtn = add
end

-- One line per comment: "Name, date: text" and a delete button on your own.
function RW:CommentRow(i)
    local row = self.commentRows[i]
    if row then return row end
    local c = self.detailContent
    row = CreateFrame("Frame", nil, c)
    row.Text = Para(row, "NootropicGM_GameFontHighlightSmall", PANEL_W - 70)
    row.Text:SetPoint("TOPLEFT", 0, 0)
    row.Delete = CreateFrame("Button", nil, row)
    row.Delete:SetSize(14, 14)
    row.Delete:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.Delete:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.Delete:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W.Tooltip(row.Delete, "Delete your comment")
    row.Delete:SetScript("OnClick", function(self)
        local rid, cid = RW.selected, self:GetParent().commentId
        W.Confirm("Delete your comment?", function()
            local ok, err = ns.Reviews:DeleteComment(rid, cid)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end)
    end)
    self.commentRows[i] = row
    return row
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
function RW:OnSubmit()
    local ok, err = ns.Reviews:Submit(self.rateStars.value, self.textBox:GetText())
    if ok then
        self.rateStars:SetValue(0)
        self.textBox:SetText("")
        self.textBox:ClearFocus()
        self.justSent = true
        ns:Print("Thanks! Your anonymous review will be delivered to the officers in a few minutes.")
    else
        self.submitError = err
    end
    self:RefreshWrite()
end

function RW:OnAddComment()
    if not self.selected then return end
    local ok, err = ns.Reviews:AddComment(self.selected, self.commentBox:GetText())
    if ok then
        self.commentBox:SetText("")
        self.commentBox:ClearFocus()
    elseif err then
        ns:Print("|cffff5555" .. err .. "|r")
    end
end

function RW:Select(id)
    self.selected = id
    self:Refresh()
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function RW:RefreshWrite()
    local RVs = ns.Reviews
    local text = self.textBox:GetText() or ""
    self.count:SetText(("%d / %d"):format(#text, RVs.TEXT_MAX))
    local wait = RVs:Wait()
    local inGuild = IsInGuild() and ns.DB:Guild() ~= nil
    self.submitBtn:SetEnabled(inGuild and wait <= 0 and self.rateStars.value > 0 and ns.Trim(text) ~= "")
    local enabled = ns.DB:ReviewsEnabled()
    if not enabled then self.submitBtn:SetEnabled(false) end
    local status
    if not inGuild then
        status = "|cff9d9d9dJoin a guild to review it.|r"
    elseif not enabled then
        status = "|cffff5555Guild reviews are turned off.|r |cff9d9d9dTick \"Guildmates can review the guild\" at the top to turn them back on.|r"
    elseif self.submitError then
        status = "|cffff5555" .. self.submitError .. "|r"
        self.submitError = nil
    elseif RVs:PendingCount() > 0 then
        status = "|cffffd100Your review will be delivered to an officer in a few minutes|r (it waits until an officer running the addon is online)."
    elseif wait > 0 then
        status = (self.justSent and "|cff40ff40Thanks, your review was delivered.|r " or "")
            .. ("|cff9d9d9dYou can write your next review in %s.|r"):format(RVs.FormatWait(wait))
    else
        status = "|cff9d9d9dPick 1 to 5 stars and write a message.|r"
    end
    self.writeStatus:SetText(status)
end

function RW:RefreshDetail(r)
    self.detailStars:SetValue(r.stars)
    self.detailDate:SetText(DayText(r.day))
    self.detailText:SetText(r.text)
    local me = ns.PlayerFullName()
    local y = -(self.detailText:GetStringHeight() or 14) - 36
    self.commentsTitle:SetText(#r.comments == 0 and "Officer comments  |cff9d9d9d(none yet)|r" or "Officer comments")
    for i, c in ipairs(r.comments) do
        local row = self:CommentRow(i)
        row.commentId = c.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, y)
        row:SetWidth(PANEL_W - 50)
        row.Text:SetText(("|cffffd100%s|r |cff9d9d9d%s|r  %s"):format(ns.ShortName(c.by or "?"), date("%b %d", c.at), c.text))
        local h = math.max(14, row.Text:GetStringHeight() or 14)
        row:SetHeight(h)
        row.Delete:SetShown(c.by == me)
        row:Show()
        y = y - h - 8
    end
    for i = #r.comments + 1, #self.commentRows do self.commentRows[i]:Hide() end
    self.detailContent:SetHeight(-y + 10)
end

function RW:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    local officer = ns.IsOfficer()
    local list = officer and ns.Reviews:List() or {}
    if self.selected and not officer then self.selected = nil end

    -- summary
    local avg, n, by = ns.Reviews:Stats(list)
    self.avgStars:SetShown(officer and n > 0)
    self.avgStars:SetValue(math.floor(avg + 0.5))
    self.enableCheck:SetShown(officer)
    self.enableCheck:SetChecked(ns.DB:ReviewsEnabled())
    if not officer then
        self.summary:SetText("Review the Guild")
        self.breakdown:SetText("")
    elseif n == 0 then
        self.summary:SetText("No reviews yet")
        self.breakdown:SetText("")
    else
        self.summary:SetText(("%.1f average from %d review%s"):format(avg, n, n == 1 and "" or "s"))
        local parts = {}
        for s = 5, 1, -1 do parts[#parts + 1] = ("%d star%s: %d"):format(s, s == 1 and "" or "s", by[s]) end
        self.breakdown:SetText(table.concat(parts, "   "))
    end
    -- the breakdown would run into the on/off switch in a narrow window
    self.breakdown:SetShown(self.frame:GetWidth() >= 940)
    if not officer then
        self.summary:ClearAllPoints()
        self.summary:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 84, -38)
    else
        self.summary:ClearAllPoints()
        self.summary:SetPoint("LEFT", self.avgStars, "RIGHT", 10, 0)
        if n == 0 then
            self.summary:ClearAllPoints()
            self.summary:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 84, -38)
        end
    end

    -- list
    for i, r in ipairs(list) do r._stripe = (i % 2 == 0) end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    self.scrollBox:SetShown(officer)
    self.scrollBar:SetShown(officer)
    if not officer then
        self.emptyText:SetText("Your review goes to the guild's officers.\n\nOnly officers can read reviews. Nobody, not even the officers, can see who wrote one.")
    elseif n == 0 then
        self.emptyText:SetText("No reviews yet. Guildmates running the addon can write one on this tab.")
    else
        self.emptyText:SetText("")
    end

    -- right panel
    local r = officer and self.selected and ns.Reviews:Get(self.selected)
    if self.selected and not r then self.selected = nil end
    self.writePane:SetShown(not r)
    self.detailPane:SetShown(r and true or false)
    if r then self:RefreshDetail(r) else self:RefreshWrite() end
end
