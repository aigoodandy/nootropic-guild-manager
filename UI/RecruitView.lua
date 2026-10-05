--[[
    Nootropic Guild Manager - Recruitment tab
    Left: /who search controls and the list of players found (unguilded, or
    members of a guild you name).
    Right: default message, custom messages switch, auto-invite, Do Not Whisper.
    Flow: search, tick the players to message, Send Whispers (paced queue).
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local RCV = {}
ns.RecruitView = RCV

local ROW_H = 26
local PANEL_W = 360
local FOOTER_H = 30
local COLUMNS = {
    { key = "pick",    label = "",         width = 28,  min = 28, locked = true },
    { key = "name",    label = "Name",     width = 120, min = 90, locked = true },
    { key = "level",   label = "Lvl",      width = 34,  min = 30, justify = "CENTER", locked = true },
    { key = "class",   label = "Class",    width = 80,  min = 60, hidePriority = 1 },
    { key = "zone",    label = "Zone",     width = 120, min = 60, hidePriority = 2, flex = true },
    { key = "status",  label = "Status",   width = 150, min = 80, hidePriority = 3 },
}
local COL = {}
for _, c in ipairs(COLUMNS) do COL[c.key] = c end

RCV.layoutVersion = 0

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function InputBox(parent, width, maxLetters, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    if maxLetters then eb:SetMaxLetters(maxLetters) end
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

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

local function ClassHexOrGray(classFile)
    if classFile and classFile ~= "" then return ns.ClassHex(classFile) end
    return "ffbbbbbb"
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function RCV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame
    page:SetScript("OnShow", function()
        RCV:OnResize()
        RCV:Refresh()
        RCV:LoadSettings()
    end)

    self:BuildSearchBar(page, frame)
    self:BuildList(page, frame.Inset)
    self:BuildPanel(page, frame.Inset)

    ns:On("RECRUITS_CHANGED", function()
        if page:IsVisible() then ns.Debounce("recruitview", 0.05, function() RCV:Refresh() end) end
    end)
    ns:On("MESSAGES_CHANGED", function()
        if page:IsVisible() then ns.Debounce("recruitview", 0.05, function() RCV:Refresh() end) end
    end)
end

function RCV:BuildSearchBar(page, frame)
    local levelLabel = Label(page, "Level")
    levelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -38)

    local minBox = InputBox(page, 26, 2, true)
    minBox:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
    local to = Label(page, "to", "GameFontHighlightSmall")
    to:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
    local maxBox = InputBox(page, 26, 2, true)
    maxBox:SetPoint("LEFT", to, "RIGHT", 10, 0)
    local function saveLevels()
        local r = ns.Recruit:Settings()
        if not r then return end
        r.query.min = tonumber(minBox:GetText()) or r.query.min
        r.query.max = tonumber(maxBox:GetText()) or r.query.max
    end
    minBox:HookScript("OnTextChanged", function(_, user) if user then saveLevels() end end)
    maxBox:HookScript("OnTextChanged", function(_, user) if user then saveLevels() end end)
    self.minBox, self.maxBox = minBox, maxBox

    local classBtn = W.Button(page, "Any class", 110, 22)
    classBtn:SetPoint("LEFT", maxBox, "RIGHT", 12, 0)
    classBtn:SetScript("OnClick", function(btn) RCV:ShowClassMenu(btn) end)
    self.classBtn = classBtn

    local zoneLabel = Label(page, "Zone")
    zoneLabel:SetPoint("LEFT", classBtn, "RIGHT", 10, 0)
    local zoneBox = InputBox(page, 110, 40)
    zoneBox:SetPoint("LEFT", zoneLabel, "RIGHT", 10, 0)
    zoneBox:HookScript("OnTextChanged", function(self, user)
        local r = ns.Recruit:Settings()
        if user and r then r.query.zone = self:GetText() end
    end)
    zoneBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.zoneBox = zoneBox

    local search = W.Button(page, "Search /who", 110, 22)
    search:SetPoint("LEFT", zoneBox, "RIGHT", 10, 0)
    -- /who is restricted to Blizzard's UI, so the click runs a secure "/who"
    -- command. This plain handler only runs when that isn't available
    -- (in combat, or on clients without secure buttons).
    search:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            ns:Print("You can't search while in combat.")
            return
        end
        local ok, err = ns.Recruit:Search()
        if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        RCV:Refresh()
    end)
    W.SecureOverlay(search, {
        macro = function() return ns.Recruit:WhoMacro() end,
        post = function() RCV:Refresh() end,
    })
    W.Tooltip(search, "Find players without a guild",
        "Runs a /who search with these filters and keeps everyone who has no guild.",
        "The game returns at most 50 players per search, so narrow level ranges find more people.",
        ("To keep you clear of spam detection, searches are limited to one every %d seconds and %d per %d minutes."):format(
            ns.Recruit.WHO_COOLDOWN, ns.Recruit.WHO_MAX_PER_WINDOW, ns.Recruit.WHO_WINDOW / 60))
    self.searchBtn = search

    -- Row 2
    local step = Check(page, "Step levels")
    step:SetPoint("TOPLEFT", frame, "TOPLEFT", 76, -58)
    step:SetScript("OnClick", function(self)
        local r = ns.Recruit:Settings()
        if r then r.query.step = self:GetChecked() and true or false end
    end)
    W.Tooltip(step, "Step through levels",
        "After each search the level range moves up by its own size (10-14, then 15-19, ...), wrapping back to 1 at max level. Keep clicking Search to sweep every level.")
    self.stepCheck = step

    local hide = Check(page, "Hide contacted")
    hide:SetPoint("LEFT", step.Label, "RIGHT", 14, -1)
    hide:SetScript("OnClick", function() RCV:Refresh() end)
    self.hideCheck = hide

    -- Search a specific guild (off by default)
    local guildCheck = Check(page, "Guild:")
    guildCheck:SetPoint("LEFT", hide.Label, "RIGHT", 14, -1)
    guildCheck:SetScript("OnClick", function(self)
        local r = ns.Recruit:Settings()
        if r then r.query.guildOn = self:GetChecked() and true or false end
        RCV:LoadSettings()
    end)
    W.Tooltip(guildCheck, "Search a guild",
        "When ticked, Search finds members of the guild named here instead of players without a guild.",
        "Your own guild is never included.")
    self.guildCheck = guildCheck
    local guildBox = InputBox(page, 120, 24)
    guildBox:SetPoint("LEFT", guildCheck.Label, "RIGHT", 8, 0)
    guildBox:HookScript("OnTextChanged", function(self, user)
        local r = ns.Recruit:Settings()
        if user and r then r.query.guild = self:GetText() end
    end)
    self.guildBox = guildBox

    local clear = W.Button(page, "Clear New", 86, 20)
    clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -59)
    clear:SetScript("OnClick", function()
        W.Confirm("Remove everyone you haven't contacted from the list?", function() ns.Recruit:ClearUncontacted() end)
    end)
    W.Tooltip(clear, "Clear the list", "Removes players you haven't whispered or invited. Contacted players are kept so you don't message them twice.")

    local status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", guildBox, "RIGHT", 12, 0)
    status:SetPoint("RIGHT", clear, "LEFT", -10, 0)
    status:SetJustifyH("RIGHT")
    status:SetWordWrap(false)
    self.statusText = status
end

function RCV:ShowClassMenu(owner)
    local r = ns.Recruit:Settings()
    if not r then return end
    local items = { { text = "Search class", isTitle = true } }
    items[#items + 1] = {
        text = "Any class", radio = true,
        checked = function() return r.query.class == nil end,
        func = function() r.query.class = nil; RCV:LoadSettings() end,
    }
    for _, classFile in ipairs(D.CLASSES) do
        items[#items + 1] = {
            text = ("|c%s%s|r"):format(ns.ClassHex(classFile), D:ClassName(classFile)),
            radio = true,
            checked = function() return r.query.class == classFile end,
            func = function() r.query.class = classFile; RCV:LoadSettings() end,
        }
    end
    W.ShowMenu(owner, items)
end

------------------------------------------------------------------------
-- Results list
------------------------------------------------------------------------
function RCV:BuildList(page, inset)
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    header:SetHeight(24)
    self.header = header
    self.headers = {}
    for _, c in ipairs(COLUMNS) do
        local h = W.ColumnHeader(header, c.label, c.width, c.justify)
        h:EnableMouse(false)
        self.headers[c.key] = h
    end

    local scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scrollBox:SetPoint("BOTTOM", inset, "BOTTOM", 0, FOOTER_H + 4)
    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, p) RCV:InitRow(row, p) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 20)
    empty:SetWidth(360)
    self.emptyText = empty

    self:BuildFooter(page, inset)
end

------------------------------------------------------------------------
-- Footer: selection and the whisper queue
------------------------------------------------------------------------
function RCV:BuildFooter(page, inset)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 4)
    f:SetHeight(FOOTER_H - 4)
    self.footer = f

    local selNew = W.Button(f, "Select New", 92, 22)
    selNew:SetPoint("LEFT", 0, 0)
    selNew:SetScript("OnClick", function() ns.Recruit:SelectNew(RCV.list or {}) end)
    W.Tooltip(selNew, "Select new players", "Ticks everyone in the list nobody in the guild has whispered yet (people on the Do Not Whisper list are never ticked).")
    local clear = W.Button(f, "Clear", 60, 22)
    clear:SetPoint("LEFT", selNew, "RIGHT", 4, 0)
    clear:SetScript("OnClick", function() ns.Recruit:ClearSelection() end)

    self.sendInfo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.sendInfo:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    self.sendInfo:SetJustifyH("LEFT")
    self.sendInfo:SetWordWrap(false)

    local send = W.Button(f, "Send Whispers", 130, 22)
    send:SetPoint("RIGHT", 0, 0)
    send:SetScript("OnClick", function() RCV:OnSendClicked() end)
    W.Tooltip(send, "Send whispers",
        ("Whispers the ticked players one at a time, %d seconds apart and at most %d per hour, so the game's spam detection is never triggered."):format(ns.Recruit.WHISPER_INTERVAL, ns.Recruit.WHISPER_MAX),
        "Hover a row to read the message that player will get.")
    self.sendBtn = send
    self.sendInfo:SetPoint("RIGHT", send, "LEFT", -8, 0)
end

-- Send / Stop / Send Next, shared by the footer and the mini recruiter.
-- order: the list as shown (whispers go out in that order), or nil.
function RCV:OnSendClicked(order)
    local RC = ns.Recruit
    local r = RC:Settings()
    if RC:IsSending() then
        if r and r.whisperMode == "click" and RC:WhisperWait() <= 0 then
            RC:SendNext(true)
        else
            RC:StopSending()
            ns:Print("Stopped sending whispers.")
        end
    else
        local n = RC:StartSending(order or self.list)
        if n == 0 then ns:Print("Tick the players you want to whisper first (or click Select New).") end
    end
    self:Refresh()
end

-- The Send button's text, whether it's clickable, and a status line.
-- short: "Send (3)" instead of "Send Whispers (3)", for the mini recruiter.
function RCV:SendState(short)
    local RC = ns.Recruit
    local r = RC:Settings()
    local selected = RC:SelectedCount()
    local wait = RC:WhisperWait()
    if RC:IsSending() then
        local left = #RC.queue
        if r and r.whisperMode == "click" then
            return wait > 0 and ("Wait %ds"):format(math.ceil(wait)) or "Send Next", true,
                ("%d waiting - click Send Next for each"):format(left)
        end
        return "Stop", true, ("Sending: %d left, next in %ds"):format(left, math.ceil(wait))
    end
    local label = short and "Send" or "Send Whispers"
    local text = selected > 0 and ("%s (%d)"):format(label, selected) or label
    if wait > 0 and #RC.sentTimes >= RC.WHISPER_MAX then
        return text, selected > 0, ("Hourly limit reached - %d min"):format(math.ceil(wait / 60))
    end
    return text, selected > 0, selected > 0 and (selected .. " selected") or "Tick players to whisper"
end

function RCV:RefreshFooter()
    local text, enabled, info = self:SendState()
    self.sendBtn:SetText(text)
    self.sendBtn:SetEnabled(enabled)
    self.sendInfo:SetText(info)
end

-- Fits columns into the list width, hiding low-priority ones when narrow.
function RCV:Layout(listW)
    local vis = {}
    for i, c in ipairs(COLUMNS) do
        c.order, c.autoHidden = i, false
        vis[#vis + 1] = c
    end
    local function sum(field)
        local n = 0
        for _, c in ipairs(vis) do n = n + c[field] end
        return n
    end
    while sum("min") > listW do
        local victim, vi
        for i, c in ipairs(vis) do
            if not c.locked and (not victim or c.hidePriority < victim.hidePriority) then victim, vi = c, i end
        end
        if not victim then break end
        victim.autoHidden = true
        table.remove(vis, vi)
    end
    -- Bring back any hidden column that fits in the space left over.
    local hidden = {}
    for _, c in ipairs(COLUMNS) do if c.autoHidden then hidden[#hidden + 1] = c end end
    table.sort(hidden, function(a, b) return a.hidePriority > b.hidePriority end)
    for _, c in ipairs(hidden) do
        if sum("min") + c.min <= listW then
            c.autoHidden = false
            vis[#vis + 1] = c
        end
    end
    table.sort(vis, function(a, b) return a.order < b.order end)
    for _, c in ipairs(COLUMNS) do c.shown = false end
    local extra = listW - sum("width")
    local flexShown = false
    for _, c in ipairs(vis) do if c.flex then flexShown = true end end
    local x = 0
    for _, c in ipairs(vis) do
        c.shown = true
        c.w = c.width
        if extra < 0 and not c.locked then
            c.w = math.max(c.min, c.width + math.floor(extra * (c.width - c.min) / math.max(1, sum("width") - sum("min"))))
        elseif extra > 0 and (c.flex or (not flexShown and c.key == "name")) then
            c.w = c.width + extra
        end
        c.x = x
        x = x + c.w
    end
    for _, c in ipairs(COLUMNS) do
        local h = self.headers[c.key]
        if c.shown then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", c.x, 0)
            h:SetColumnWidth(c.w)
            h:Show()
        else
            h:Hide()
        end
    end
    self.header:SetWidth(listW)
    self.scrollBox:SetWidth(listW)
    if self.footer then self.footer:SetWidth(listW) end
    self.layoutVersion = self.layoutVersion + 1
end

function RCV:OnResize()
    if not self.frame then return end
    local listW = math.floor(self.frame:GetWidth() - 10 - 4 - 22 - PANEL_W - 14)
    if listW == self.listW then return end
    self.listW = listW
    self:Layout(listW)
    if self.scrollBox.ForEachFrame then
        self.scrollBox:ForEachFrame(function(row) if row.person then RCV:InitRow(row, row.person) end end)
    end
end

local function Text(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.35)

    row.cells = {}
    for _, c in ipairs(COLUMNS) do
        local cell = CreateFrame("Frame", nil, row)
        cell:SetHeight(ROW_H)
        row.cells[c.key] = cell
    end
    local cells = row.cells

    row.ClassIcon = cells.name:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetSize(16, 16)
    row.ClassIcon:SetPoint("LEFT", 6, 0)
    row.Name = cells.name:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Name:SetPoint("LEFT", row.ClassIcon, "RIGHT", 5, 0)
    row.Name:SetPoint("RIGHT", -4, 0)

    row.Level = Text(cells.level, "CENTER")
    row.Level:SetAllPoints()
    row.Class = Text(cells.class)
    row.Class:SetPoint("LEFT", 6, 0)
    row.Class:SetPoint("RIGHT", -4, 0)
    row.Zone = Text(cells.zone)
    row.Zone:SetPoint("LEFT", 6, 0)
    row.Zone:SetPoint("RIGHT", -4, 0)
    row.Status = Text(cells.status)
    row.Status:SetPoint("LEFT", 6, 0)
    row.Status:SetPoint("RIGHT", -4, 0)

    row.Pick = CreateFrame("CheckButton", nil, cells.pick, "UICheckButtonTemplate")
    row.Pick:SetSize(22, 22)
    row.Pick:SetPoint("CENTER", 0, 0)
    row.Pick:SetScript("OnClick", function(self)
        if row.person then ns.Recruit:SetSelected(row.person.full, self:GetChecked()) end
    end)
    row.Pick:SetScript("OnEnter", function() RCV:ShowRowTooltip(row, row.person) end)
    row.Pick:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self, button)
        local p = self.person
        if not p then return end
        if button == "RightButton" then
            RCV:ShowRowMenu(self, p)
        elseif ns.Recruit:CanSelect(p) then
            ns.Recruit:SetSelected(p.full, not ns.Recruit.selected[p.full])
        end
    end)
    row:SetScript("OnEnter", function(self) RCV:ShowRowTooltip(self, self.person) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function StatusLabel(p)
    local st = ns.Recruit:Status(p)
    if st == "joined" then return "|cff40ff40Joined!|r" end
    if st == "dnw" then return "|cffff5555Do not whisper|r" end
    local c = ns.Recruit:Contact(p)
    local by = c.by and ("|cff9d9d9d by|r |cffffffff" .. ns.ShortName(c.by) .. "|r") or ""
    if st == "invited" then return "|cffffd100Invited|r" .. by end
    if st == "replied" then return "|cff40ff40Replied|r |cff9d9d9d" .. ns.FormatAgo(c.replied) .. "|r" .. by end
    if st == "whispered" then return "|cffb0b0ffWhispered|r |cff9d9d9d" .. ns.FormatAgo(c.whispered) .. "|r" .. by end
    return "|cff9d9d9dNew|r"
end
RCV.StatusLabel = StatusLabel

function RCV:InitRow(row, p)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    if row.layoutVersion ~= self.layoutVersion then
        for _, c in ipairs(COLUMNS) do
            local cell = row.cells[c.key]
            if c.shown then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", c.x, 0)
                cell:SetWidth(c.w)
                cell:Show()
            else
                cell:Hide()
            end
        end
        row.layoutVersion = self.layoutVersion
    end
    row.person = p
    row.Stripe:SetShown(p._stripe)
    W.SetClassIcon(row.ClassIcon, p.classFile)
    row.Name:SetText(p.short)
    row.Name:SetTextColor(ns.ClassColor(p.classFile))
    row.Level:SetText(p.level or "")
    row.Class:SetText(p.className or "")
    row.Class:SetTextColor(ns.ClassColor(p.classFile))
    row.Zone:SetText((p.zone or "") .. (p.guild and ("  |cff9d9d9d<" .. p.guild .. ">|r") or ""))
    row.Status:SetText(StatusLabel(p))
    local canPick = ns.Recruit:CanSelect(p)
    local queued = false
    for _, f in ipairs(ns.Recruit.queue) do if f == p.full then queued = true break end end
    row.Pick:SetChecked((ns.Recruit.selected[p.full] or queued) and true or false)
    row.Pick:SetEnabled(canPick and not queued)
    if queued then row.Status:SetText("|cffffd100Queued|r") end
end


function RCV:ShowRowTooltip(row, p)
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.short, ns.ClassColor(p.classFile))
    GameTooltip:AddLine(("Level %s %s"):format(p.level or "?", p.className or ""), 1, 1, 1)
    if p.zone and p.zone ~= "" then GameTooltip:AddLine(p.zone, 0.8, 0.8, 0.8) end
    if p.guild then GameTooltip:AddLine("<" .. p.guild .. ">", 0.25, 1, 0.25) end
    if ns.Recruit:IsDNW(p.full) then GameTooltip:AddLine("On the Do Not Whisper list", 1, 0.35, 0.35) end
    if p.race then GameTooltip:AddLine(p.race, 0.8, 0.8, 0.8) end
    local text, rule = ns.Recruit:TemplateFor(p)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Message: " .. (rule and rule.name or "Default"), 1, 0.82, 0)
    local msg = ns.Recruit:Format(text, p)
    GameTooltip:AddLine(msg ~= "" and ("|cffff80ff" .. msg .. "|r") or "|cff9d9d9d(empty - write a message first)|r", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    local c = ns.Recruit:Contact(p)
    GameTooltip:AddDoubleLine("Found", ns.FormatAgo(p.found), 1, 0.82, 0, 1, 1, 1)
    if c.whispered then GameTooltip:AddDoubleLine("Whispered", ns.FormatAgo(c.whispered), 1, 0.82, 0, 1, 1, 1) end
    if c.reply then
        GameTooltip:AddLine("Their reply:", 1, 0.82, 0)
        GameTooltip:AddLine("\"" .. c.reply .. "\"", 0.4, 1, 0.4, true)
    end
    if c.invited then GameTooltip:AddDoubleLine("Invited", ns.FormatAgo(c.invited), 1, 0.82, 0, 1, 1, 1) end
    if c.by then
        GameTooltip:AddLine(("Already contacted by %s, so they can't be whispered again for now."):format(ns.ShortName(c.by)), 1, 0.5, 0.5, true)
    end
    if p.joined then GameTooltip:AddDoubleLine("Joined", ns.FormatAgo(p.joined), 1, 0.82, 0, 0.4, 1, 0.4) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to tick or untick. Right-click for more options.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function RCV:ShowRowMenu(row, p)
    local dnw = ns.Recruit:IsDNW(p.full)
    local whispered = ns.Recruit:Contact(p).whispered
    W.ShowMenu(row, {
        { text = p.short, isTitle = true },
        { text = whispered and "Invite to Guild" or "Invite to Guild (whisper them first)",
          disabled = p.joined or dnw or not whispered or not ns.Recruit:CanInvite(),
          func = function()
              local ok, err = ns.Recruit:Invite(p.full, false)
              if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
          end },
        { divider = true },
        dnw and { text = "Take off Do Not Whisper list", func = function() ns.Recruit:RemoveDNW(p.full) end }
            or { text = "Add to Do Not Whisper list", func = function() ns.Recruit:AddDNW(p.full, "(added by hand)") end },
        { text = "Remove from list", func = function() ns.Recruit:Remove(p.full) end },
    })
end

------------------------------------------------------------------------
-- Settings panel
------------------------------------------------------------------------
function RCV:BuildPanel(page, inset)
    local panel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    panel:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -6, -4)
    panel:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
    panel:SetWidth(PANEL_W)
    panel:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0, 0, 0, 0.35)
    panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    self.panel = panel

    -- The settings scroll, so they fit short windows too.
    local scroll = W.TryCreate("ScrollFrame", nil, panel, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 3, -4)
    scroll:SetPoint("BOTTOMRIGHT", -25, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_W - 28, 640)
    scroll:SetScrollChild(content)
    self.panelContent = content
    panel = content -- everything below is placed in the scrolling area
    local IW = PANEL_W - 52

    local title, line = W.SectionHeader(panel, "Whisper Messages")
    title:SetPoint("TOPLEFT", 12, -12)
    line:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    -- Everything below is placed under the element above it, so text that
    -- wraps pushes the rest down instead of overlapping it.
    local dlabel = Label(panel, "Default message")
    dlabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local dhint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dhint:SetPoint("LEFT", dlabel, "RIGHT", 6, 0)
    dhint:SetText("(when no custom message fits)")

    local editorFrame, box = W.ScrollEditor(panel, D.WHISPER_MAX)
    editorFrame:SetPoint("TOPLEFT", dlabel, "BOTTOMLEFT", 2, -6)
    editorFrame:SetSize(IW - 4, 66)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(IW - 22)
    box:HookScript("OnTextChanged", function(self, user)
        if user then ns.Recruit:SetDefault(self:GetText()) end
        RCV:RefreshPreview()
    end)
    self.editor = box

    self.tokens = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.tokens:SetPoint("TOPLEFT", editorFrame, "BOTTOMLEFT", -2, -6)
    self.tokens:SetWidth(IW)
    self.tokens:SetJustifyH("LEFT")
    self.tokens:SetText("|cffffd100$name $class $level $race $zone $guild|r are filled in")

    self.preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.preview:SetPoint("TOPLEFT", self.tokens, "BOTTOMLEFT", 0, -6)
    self.preview:SetWidth(IW)
    self.preview:SetJustifyH("LEFT")
    self.preview:SetSpacing(2)

    local use = Check(panel, "Use custom messages")
    use:SetPoint("TOPLEFT", self.preview, "BOTTOMLEFT", -4, -8)
    use:SetScript("OnClick", function(self) ns.Messages:SetUseRules(self:GetChecked()) end)
    W.Tooltip(use, "Custom messages",
        "Pick a message by class, race, level, zone or guild. The first matching message (top of the list wins) is used; everyone else gets the Default message.")
    self.useRulesCheck = use

    local edit = W.Button(panel, "Custom Messages...", 150, 22)
    edit:SetPoint("TOPLEFT", use, "BOTTOMLEFT", 4, -4)
    edit:SetScript("OnClick", function() ns.MessagesView:Toggle() end)
    self.rulesButton = edit
    self.rulesInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.rulesInfo:SetPoint("LEFT", edit, "RIGHT", 8, 0)

    -- Auto-invite
    local title2, line2 = W.SectionHeader(panel, "Auto-Invite")
    title2:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -18)
    line2:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    local auto = Check(panel, "Invite when they reply with a keyword")
    auto:SetPoint("TOPLEFT", title2, "BOTTOMLEFT", -4, -4)
    auto:SetScript("OnClick", function(self)
        local r = ns.Recruit:Settings()
        if r then r.autoInvite = self:GetChecked() and true or false end
    end)
    self.autoCheck = auto

    local confirm = Check(panel, "Ask me first (one-click Invite popup)")
    confirm:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, 0)
    confirm:SetScript("OnClick", function(self)
        local r = ns.Recruit:Settings()
        if r then r.inviteMode = self:GetChecked() and "confirm" or "auto" end
    end)
    self.confirmCheck = confirm

    local kwLabel = Label(panel, "Keywords (whole words, any case)")
    kwLabel:SetPoint("TOPLEFT", confirm, "BOTTOMLEFT", 4, -6)

    local BOX_W, BOX_STEP = 88, 100
    self.keywordBoxes = {}
    for i = 1, D.MAX_KEYWORDS do
        local eb = InputBox(panel, BOX_W, 24)
        local col, rowN = (i - 1) % 3, math.floor((i - 1) / 3)
        eb:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", 6 + col * BOX_STEP, -4 - rowN * 24)
        eb:HookScript("OnTextChanged", function(self, user)
            local r = ns.Recruit:Settings()
            if user and r then r.keywords[i] = ns.Trim(self:GetText()) end
        end)
        self.keywordBoxes[i] = eb
    end

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", 0, -56)
    help:SetWidth(IW)
    help:SetJustifyH("LEFT")
    help:SetText("Only replies from players you whispered from this tab are checked.")

    -- Do Not Whisper
    local title3, line3 = W.SectionHeader(panel, "Do Not Whisper")
    title3:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -18)
    line3:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    local dnw = Check(panel, "Do Not Whisper list")
    dnw:SetPoint("TOPLEFT", title3, "BOTTOMLEFT", -4, -4)
    dnw:SetScript("OnClick", function(self)
        local r = ns.Recruit:Settings()
        if r then r.dnwEnabled = self:GetChecked() and true or false end
    end)
    W.Tooltip(dnw, "Do Not Whisper list",
        "When someone you whispered replies with one of these words, they're added to the list and never whispered or invited again.",
        "Untick to stop adding people. Anyone already on the list stays protected until you remove them.")
    self.dnwCheck = dnw

    local dnwLabel = Label(panel, "Words (whole words, any case)")
    dnwLabel:SetPoint("TOPLEFT", dnw, "BOTTOMLEFT", 4, -6)
    self.dnwBoxes = {}
    for i = 1, D.MAX_KEYWORDS do
        local eb = InputBox(panel, BOX_W, 32)
        local col, rowN = (i - 1) % 3, math.floor((i - 1) / 3)
        eb:SetPoint("TOPLEFT", dnwLabel, "BOTTOMLEFT", 6 + col * BOX_STEP, -4 - rowN * 24)
        eb:HookScript("OnTextChanged", function(self, user)
            local r = ns.Recruit:Settings()
            if user and r then r.dnwWords[i] = ns.Trim(self:GetText()) end
        end)
        self.dnwBoxes[i] = eb
    end

    self.dnwCount = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.dnwCount:SetPoint("TOPLEFT", dnwLabel, "BOTTOMLEFT", 0, -60)
    local view = W.Button(panel, "View List", 90, 20)
    view:SetPoint("LEFT", self.dnwCount, "LEFT", IW - 90, 0)
    view:SetScript("OnClick", function(btn) RCV:ShowDNWMenu(btn) end)
    W.Tooltip(view, "Do Not Whisper list", "Shared with everyone in the guild using the addon. Click a name to take them off it.")
    self.dnwView = view
    self.panelLast = view

    -- Grow the scroll area to fit (the preview's height changes with the text).
    self.panelTitle = title
    content:SetScript("OnSizeChanged", function() RCV:FitPanel() end)
end

function RCV:FitPanel()
    local content, last = self.panelContent, self.panelLast
    if not (content and last) then return end
    local top, bottom = content:GetTop(), last:GetBottom()
    if top and bottom and top > bottom then content:SetHeight(math.ceil(top - bottom) + 16) end
end

function RCV:ShowDNWMenu(owner)
    local list = ns.Recruit:DNWList()
    local items = { { text = ("Do Not Whisper (%d)"):format(#list), isTitle = true } }
    for i, d in ipairs(list) do
        if i > 40 then
            items[#items + 1] = { text = ("...and %d more"):format(#list - 40), disabled = true }
            break
        end
        items[#items + 1] = {
            text = ("%s  |cff9d9d9d%s, by %s|r"):format(ns.ShortName(d.full), date("%b %d", d.at), ns.ShortName(d.by or "?")),
            func = function()
                W.Confirm(("Take %s off the Do Not Whisper list?\nThey said: \"%s\""):format(ns.ShortName(d.full), d.reply or "?"),
                    function() ns.Recruit:RemoveDNW(d.full) end)
            end,
        }
    end
    if #list == 0 then items[2] = { text = "Nobody yet", disabled = true } end
    W.ShowMenu(owner, items)
end

function RCV:RefreshPreview()
    if not self.preview then return end
    local r = ns.Recruit:Settings()
    local sample = { short = "Thrall", full = "Thrall", classFile = "WARRIOR", className = "Warrior", level = 42,
        race = "Orc", zone = "Durotar" }
    local text = ns.Recruit:Format(r and r.default or "", sample)
    self.preview:SetText("|cffffd100Preview:|r " .. (text ~= "" and ("|cffff80ff" .. text .. "|r") or "|cff9d9d9d(empty)|r")
        .. ("  |cff6d6d6d%d/%d|r"):format(#text, D.WHISPER_MAX))
    self:FitPanel()
end

function RCV:RefreshRulesInfo()
    local r = ns.Recruit:Settings()
    if not (r and self.rulesInfo) then return end
    local on = 0
    for _, rule in ipairs(r.rules or {}) do if rule.enabled then on = on + 1 end end
    self.useRulesCheck:SetChecked(r.useRules)
    self.rulesInfo:SetText(("%d message%s, %d on"):format(#(r.rules or {}), #(r.rules or {}) == 1 and "" or "s", on))
    self.rulesButton:SetAlpha(r.useRules and 1 or 0.6)
end

function RCV:LoadSettings()
    local r = ns.Recruit:Settings()
    if not r then return end
    local q = r.query
    if not self.minBox:HasFocus() then self.minBox:SetText(tostring(q.min or 1)) end
    if not self.maxBox:HasFocus() then self.maxBox:SetText(tostring(q.max or 60)) end
    if not self.zoneBox:HasFocus() then self.zoneBox:SetText(q.zone or "") end
    self.classBtn:SetText(q.class and ("|c%s%s|r"):format(ns.ClassHex(q.class), D:ClassName(q.class)) or "Any class")
    self.stepCheck:SetChecked(q.step)
    self.guildCheck:SetChecked(q.guildOn)
    if not self.guildBox:HasFocus() then self.guildBox:SetText(q.guild or "") end
    self.guildBox:SetAlpha(q.guildOn and 1 or 0.5)
    self.dnwCheck:SetChecked(r.dnwEnabled)
    for i, eb in ipairs(self.dnwBoxes) do
        if not eb:HasFocus() then eb:SetText(r.dnwWords[i] or "") end
    end
    self.autoCheck:SetChecked(r.autoInvite)
    self.confirmCheck:SetChecked(r.inviteMode == "confirm")
    for i, eb in ipairs(self.keywordBoxes) do
        if not eb:HasFocus() then eb:SetText(r.keywords[i] or "") end
    end
    if not self.editor:HasFocus() then self.editor:SetText(r.default or "") end
    self:RefreshPreview()
    self:RefreshRulesInfo()
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
-- The Search button's text and whether it's clickable (shared with the mini recruiter).
function RCV:SearchState()
    local RC = ns.Recruit
    local wait = RC:CooldownRemaining()
    if RC.searching then return "Searching...", false end
    if wait > 0 then return ("Wait %ds"):format(math.ceil(wait)), false end
    return "Search /who", RC:Settings() ~= nil
end

-- Keep refreshing every second while a countdown is visible.
function RCV:IsShownTicking()
    local RC = ns.Recruit
    return RC:IsSending() or RC:CooldownRemaining() > 0
end

function RCV:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    local RC = ns.Recruit
    local r = RC:Settings()

    local list = RC:List({ hideContacted = self.hideCheck:GetChecked() })
    self.list = list
    for i, p in ipairs(list) do p._stripe = (i % 2 == 0) end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)

    if not r then
        self.emptyText:SetText("Join a guild to start recruiting.")
    elseif #list == 0 then
        self.emptyText:SetText("Set a level range and click Search /who to find players without a guild.")
    else
        self.emptyText:SetText("")
    end

    local searchText, searchOn = self:SearchState()
    self.searchBtn:SetText(searchText)
    self.searchBtn:SetEnabled(searchOn)

    local last = RC.last
    if RC.searching then
        self.statusText:SetText("|cffffd100Searching:|r " .. (RC.pendingQuery or ""))
    elseif last and last.timedOut then
        self.statusText:SetText("|cffff8080No reply from /who. The server limits how often you can search - wait a few seconds.|r")
    elseif last then
        local capped = (last.total or 0) > (last.shown or 0)
        self.statusText:SetText(("%d players, %d %s, |cff40ff40%d new|r%s%s"):format(
            last.total or 0, last.matched or last.unguilded or 0,
            last.guild and ("in <" .. last.guild .. ">") or "unguilded", last.new or 0,
            (last.skipped or 0) > 0 and ("  |cffff8080" .. last.skipped .. " do-not-whisper skipped|r") or "",
            capped and "  |cffff8080(capped at 50 - narrow the range)|r" or ""))
    else
        self.statusText:SetText(("%d in list"):format(#list))
    end

    self:RefreshFooter()
    self:RefreshRulesInfo()
    if self:IsShownTicking() then
        if not self.ticking then
            self.ticking = true
            C_Timer.After(1, function()
                RCV.ticking = false
                if RCV.page:IsVisible() then RCV:Refresh() end
            end)
        end
    end

    if self.dnwCount then
        local n = #ns.Recruit:DNWList()
        self.dnwCount:SetText(n == 1 and "1 person on the list" or (n .. " people on the list"))
    end

    if r and not self.minBox:HasFocus() and not self.maxBox:HasFocus() then
        self.minBox:SetText(tostring(r.query.min or 1))
        self.maxBox:SetText(tostring(r.query.max or 60))
    end
end
