--[[
    Nootropic Guild Manager - Hall of Fame tab (everyone)
    Leaderboards from the character statistics guildmates share
    (Services/HallOfFame.lua): one card per statistic with the top five,
    guild totals on top. All time, this month or last month
    (Settings().hofPeriod). People count once, their characters added up,
    always: a person counts once on every card.
]]
local _, ns = ...
local W = ns.Widgets
local HV = {}
ns.HallOfFameView = HV

local GRAY = "|cff9d9d9d"
local PERIODS = { { "all", "All time" }, { "month", "This month" }, { "last", "Last month" } }
local TOP = 5
local ROW_H = 16
local CARD_W, CARD_GAP = 230, 12
local CARD_H = 26 + TOP * ROW_H + 20 + 16 -- title, rows, last month's champion, footer
local TOTALS = { "quests", "kills", "bosses", "deaths" }

local function Me() return ns.PlayerFullName() end

function HV:Period()
    local p = ns.DB:Settings().hofPeriod
    for _, d in ipairs(PERIODS) do if d[1] == p then return p end end
    return "all"
end

local function PeriodText(p)
    for _, d in ipairs(PERIODS) do if d[1] == p then return d[2] end end
    return p
end

-- 1234567 -> "1,234,567"
function HV.Number(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
-- ns.HallOfFame:Boards for the chosen period, plus which entry is you and
-- last month's champions: { ..., mine = person key, champions = { key = {...} } }
function HV:Boards()
    local month = ns.HallOfFame.Month()
    local data = ns.HallOfFame:Boards(self:Period(), month)
    local me = Me()
    local myEntry = me and ns.Roster.byName[me]
    if myEntry then data.mine = myEntry.main or myEntry.full end
    -- the cards show the champions officers recorded (they match the titles);
    -- nil while the month's numbers are still being tallied
    data.champions = ns.HallOfFame:RecordedChampions(month)
    data.crown = ns.HallOfFame:CrownStatus()
    return data
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function Card(parent)
    -- as the dashboard's cards: a dark box with a notched edge, the title in
    -- yellow upper case, names plain, yours in aqua, last month's in yellow
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(CARD_H)
    ns.Theme:Box(c, ns.Theme.C.bg1, ns.Theme.C.edge, 4)
    c.Icon = c:CreateTexture(nil, "ARTWORK")
    c.Icon:SetSize(18, 18)
    c.Icon:SetPoint("TOPLEFT", 8, -7)
    c.Title = c:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    c.Title:SetPoint("LEFT", c.Icon, "RIGHT", 6, 0)
    c.Title:SetPoint("RIGHT", -8, 0)
    c.Title:SetJustifyH("LEFT")
    c.Title:SetWordWrap(false)
    c.rows = {}
    for i = 1, TOP do
        local r = {}
        r.Rank = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
        r.Rank:SetPoint("TOPLEFT", 10, -28 - (i - 1) * ROW_H)
        r.Rank:SetWidth(16)
        r.Rank:SetJustifyH("RIGHT")
        r.Name = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        r.Name:SetPoint("LEFT", r.Rank, "RIGHT", 6, 0)
        r.Name:SetJustifyH("LEFT")
        r.Name:SetWordWrap(false)
        r.Value = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        r.Value:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * ROW_H)
        r.Value:SetJustifyH("RIGHT")
        r.Name:SetPoint("RIGHT", r.Value, "LEFT", -6, 0)
        c.rows[i] = r
    end
    c.Champ = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.Champ:SetPoint("TOPLEFT", 10, -28 - TOP * ROW_H - 4)
    c.Champ:SetPoint("RIGHT", -10, 0)
    c.Champ:SetJustifyH("LEFT")
    c.Champ:SetWordWrap(false)
    c.You = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.You:SetPoint("BOTTOMLEFT", 10, 7)
    c.You:SetPoint("BOTTOMRIGHT", -10, 7)
    c.You:SetJustifyH("LEFT")
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self) HV:ShowCardTip(self) end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local AQUA = "|cff40c0ff"
local function NameText(p, mine)
    return p.key == mine and (AQUA .. p.e.short .. "|r") or p.e.short
end

function HV:FillCard(c, stat, data)
    local list = data.boards[stat.key]
    c.stat, c.list = stat, list
    W.SetIcon(c.Icon, stat.icon)
    c.Title:SetText(ns.Theme.Upper(stat.label))
    for i, r in ipairs(c.rows) do
        local p = list[i]
        if p then
            r.Rank:SetText(i .. ".")
            r.Name:SetText(NameText(p, data.mine))
            local v = ns.HallOfFame.Format(stat, p.n)
            r.Value:SetText(p.key == data.mine and (AQUA .. v .. "|r") or v)
        else
            r.Rank:SetText("")
            r.Name:SetText(i == 1 and (GRAY .. "Nobody yet|r") or "")
            r.Value:SetText("")
        end
    end
    local you = ""
    for i, p in ipairs(list) do
        if p.key == data.mine then
            if i > TOP then you = ("You: #%d with %s"):format(i, ns.HallOfFame.Format(stat, p.n)) end
            break
        end
    end
    if you == "" and #list > 0 then
        you = ("Guild: %s"):format(ns.HallOfFame.Format(stat, data.totals[stat.key] or 0))
    end
    c.You:SetText(you)
    -- last month's champion(s): winner takes all, ties share it
    local champ = data.champions and data.champions[stat.key]
    c.champ = champ
    if stat.noChampion then
        c.Champ:SetText(GRAY .. "Titles won, all time and by month.|r")
    elseif champ then
        local names = {}
        for i, p in ipairs(champ.winners) do
            if i > 2 then names[#names + 1] = ("+%d"):format(#champ.winners - 2) break end
            names[#names + 1] = p.e.short
        end
        c.Champ:SetText(ns.GOLD .. "Last month: " .. table.concat(names, ", ") .. "|r" .. GRAY .. " (" .. ns.HallOfFame.Format(stat, champ.n) .. ")|r")
    elseif data.crown and (data.crown.state == "tallying" or data.crown.state == "due") then
        c.Champ:SetText(GRAY .. "Last month: tallying...|r")
    else
        c.Champ:SetText(GRAY .. "Last month: no champion|r")
    end
end

-- "Tuesday 1 December, 7 pm" in your own time zone; "in 3 days" / "in 5 hours".
function HV.When(t)
    local d = date("*t", t)
    local HF = ns.HallOfFame
    return ("%s %d %s, %s"):format(date("%A", t), d.day, HF.MONTH_NAMES[d.month], ns.Profile.HourText(d.hour))
end

function HV.In(t)
    local s = t - ns.DB:Now()
    if s <= 0 then return "now" end
    if s >= 2 * 86400 then return ("in %d days"):format(math.floor(s / 86400)) end
    if s >= 2 * 3600 then return ("in %d hours"):format(math.floor(s / 3600)) end
    return ("in %d minutes"):format(math.max(1, math.floor(s / 60)))
end

-- The line about when champions are crowned.
function HV.CrownText(c)
    local HF = ns.HallOfFame
    if not c then return "" end
    local won, nextWon = HF.MonthName(c.won), HF.MonthName(c.nextWon)
    if c.state == "tallying" then
        return ((ns.GOLD .. "%s is over!|r Points are being tallied: champions will be crowned %s (%s).")):format(won, HV.When(c.at), HV.In(c.at))
    elseif c.state == "due" and HF:PeonCrowns() then
        return ((ns.GOLD .. "%s's champions are crowned by NGM Peon.|r They show here once an officer brings them in (|cffffffff/ngm peon|r).")):format(won)
    elseif c.state == "due" then
        return ((ns.GOLD .. "%s's points are tallied.|r Champions will be crowned as soon as an officer logs in.")):format(won)
    elseif c.state == "crowned" then
        local recount = HF:PeonCrowns() and " Crowned by NGM Peon."
            or HF:InRecount() and (" Late numbers can still change them until %s."):format(HV.When(c.at + HF.RECOUNT)) or ""
        return ((ns.GOLD .. "%s's champions have been crowned!|r%s Next: %s's, %s (%s).")):format(won, recount, nextWon, HV.When(c.nextAt), HV.In(c.nextAt))
    end
    return ("Next champions (%s's) crowned %s (%s)."):format(nextWon, HV.When(c.nextAt), HV.In(c.nextAt))
end

function HV:ShowCardTip(c)
    if not c.stat then return end
    GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.stat.label .. GRAY .. "  " .. PeriodText(self:Period()) .. "|r")
    if c.stat.tip then GameTooltip:AddLine(c.stat.tip, 1, 1, 1, true) end
    local mine = self.data and self.data.mine
    for i, p in ipairs(c.list or {}) do
        if i > 15 then GameTooltip:AddLine(("...and %d more"):format(#c.list - 15), 0.6, 0.6, 0.6) break end
        GameTooltip:AddDoubleLine(i .. ". " .. NameText(p, mine), ns.HallOfFame.Format(c.stat, p.n), 1, 1, 1, 1, 1, 1)
    end
    if self.data and self.data.totals[c.stat.key] then
        GameTooltip:AddDoubleLine("Guild total", ns.HallOfFame.Format(c.stat, self.data.totals[c.stat.key]), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    if c.champ then
        local names = {}
        for i, p in ipairs(c.champ.winners) do names[i] = p.e.short end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((#names > 1 and "Last month's champions (tied): " or "Last month's champion: ") .. table.concat(names, ", "), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], true)
    end
    GameTooltip:Show()
end

function HV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)

    local periodBtn = W.Button(page, "", 120, 22)
    periodBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    periodBtn:SetScript("OnClick", function(btn)
        local items = { { text = "Show", isTitle = true } }
        for _, d in ipairs(PERIODS) do
            items[#items + 1] = { text = d[2], radio = true,
                checked = function() return HV:Period() == d[1] end,
                func = function() ns.DB:Settings().hofPeriod = d[1]; HV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(periodBtn, "Period", "All time, or just this month or last month (UTC). A member's first month counts from when they installed the addon.")
    self.periodButton = periodBtn

    -- officers: post last month's champions to guild chat (one click, never automatic)
    local announce = W.Button(page, "Announce Champions", 150, 22)
    announce:SetPoint("RIGHT", periodBtn, "LEFT", -8, 0)
    announce:SetMotionScriptsWhileDisabled(true)
    announce:SetScript("OnClick", function()
        local ok, why = ns.HallOfFame:Announce()
        if not ok and why then ns:Print(why) end
        HV:Refresh()
    end)
    announce:SetScript("OnEnter", function(btn)
        local HF = ns.HallOfFame
        local won = HF.PrevMonth(HF.Month())
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Announce " .. HF.MonthName(won) .. "'s champions")
        local lines = HF:AnnounceLines(won)
        if lines then
            GameTooltip:AddLine("Posts to guild chat:", 1, 1, 1)
            for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.25, 1, 0.25, true) end
        else
            GameTooltip:AddLine("Not recorded yet: an officer's addon writes down last month's champions on the 2nd.", 1, 1, 1, true)
        end
        -- shared by every officer: who announced last, and whether the
        -- recount changed the champions after that (by anyone)
        local line = HF:AnnounceStatus(won)
        if line then GameTooltip:AddLine(line.text, line.r, line.g, line.b, true) end
        GameTooltip:Show()
    end)
    announce:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.announceButton = announce


    local inset = frame.Inset
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMHallOfFameScroll", page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    self.content = content

    self.totals = content:CreateFontString(nil, "OVERLAY", "NGMFontText")
    self.totals:SetPoint("TOPLEFT", 0, 0)
    self.totals:SetJustifyH("LEFT")
    -- who's missing from the board: guildmates without the addon
    self.crownLine = content:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.crownLine:SetPoint("TOPLEFT", self.totals, "BOTTOMLEFT", 0, -6)
    self.crownLine:SetJustifyH("LEFT")
    self.gap = content:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.gap:SetPoint("TOPLEFT", self.crownLine, "BOTTOMLEFT", 0, -6)
    self.gap:SetJustifyH("LEFT")
    self.gapButton = W.Button(content, "List them", 80, 18, "alt")
    self.gapButton:SetPoint("LEFT", self.gap, "RIGHT", 8, 0)
    self.gapButton:SetScript("OnClick", function() ns.UI:SetSearch("is:missing") end)
    W.Tooltip(self.gapButton, "Not on the board yet", "Lists them on the Find tab. Right-click someone there (or open their profile) to remind them to install the addon.")
    self.cards = {}
    self.note = content:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.note:SetJustifyH("LEFT")

    local function later() if page:IsVisible() then ns.Debounce("hofview", 0.3, function() HV:Refresh() end) end end
    page:SetScript("OnShow", function()
        ns.Roster:Request()
        ns.HallOfFame:Publish() -- your own numbers, fresh
        HV:Refresh()
    end)
    page:SetScript("OnSizeChanged", later)
    ns:On("ROSTER_UPDATED", later)
    ns:On("MEMBER_CHANGED", later)
    ns:On("HALL_OF_FAME_CHANGED", later)
end

function HV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local data = self:Boards()
    self.data = data
    local period = self:Period()
    self.periodButton:SetText(PeriodText(period))
    local HF = ns.HallOfFame
    self.announceButton:SetShown(HF:CanAnnounce())
    self.announceButton:SetEnabled(HF:AnnounceLines(HF.PrevMonth(HF.Month())) ~= nil)
    self.title:SetText(("Hall of Fame  " .. GRAY .. "- %d of %d people sharing|r"):format(data.sharing, data.people))

    local width = math.max(300, math.floor(self.scroll:GetWidth()))
    local parts = {}
    for _, k in ipairs(TOTALS) do
        local s = ns.HallOfFame.BY_KEY[k]
        parts[#parts + 1] = ns.GOLD .. HV.Number(data.totals[k] or 0) .. "|r " .. s.label:lower()
    end
    self.totals:SetWidth(width)
    self.totals:SetText("Together: " .. table.concat(parts, GRAY .. "  ·  |r"))
    local top = math.max(16, self.totals:GetStringHeight()) + 12
    self.crownLine:SetWidth(width)
    self.crownLine:SetText(HV.CrownText(data.crown))
    top = top + math.max(14, self.crownLine:GetStringHeight()) + 6
    local who = data.noAddon == 1 and "guildmate" or "guildmates"
    self.gap:SetShown(data.noAddon > 0)
    self.gapButton:SetShown(data.noAddon > 0)
    if data.noAddon > 0 then
        local text = ("%d %s aren't on the board yet: no addon."):format(data.noAddon, who)
        if data.noAddon == 1 then text = text:gsub("aren't", "isn't") end
        self.gap:SetText(text)
        top = top + 24
    end

    -- the cards' edges sit outside them: keep 4 units clear all round
    local inner = width - 8
    local cols = math.max(1, math.floor((inner + CARD_GAP) / (CARD_W + CARD_GAP)))
    local cardW = math.floor((inner - (cols - 1) * CARD_GAP) / cols)
    top = top + 4
    for i, stat in ipairs(ns.HallOfFame.STATS) do
        local c = self.cards[i] or Card(self.content)
        self.cards[i] = c
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 4 + col * (cardW + CARD_GAP), -(top + row * (CARD_H + CARD_GAP)))
        c:SetWidth(cardW)
        self:FillCard(c, stat, data)
        c:Show()
    end
    local rows = math.ceil(#ns.HallOfFame.STATS / cols)
    local y = top + rows * (CARD_H + CARD_GAP)

    local note
    if not ns.HallOfFame:Available() then
        note = "This game client doesn't give addons character statistics, so there's nothing to show."
    elseif data.sharing == 0 then
        note = "Nobody has shared their statistics yet. Each member's own addon shares them a little after they log in."
    else
        note = "From the game's own statistics (the Statistics page of the achievement window), shared by each member's addon. "
            .. "Members without the addon, or who turned off \"Share my statistics\" (Options > Sharing), aren't listed. Gold is never shared."
    end
    note = note .. " A person's main and alts count as one."
    if period ~= "all" then
        note = note .. " Months run in UTC; a member's first month counts from when they installed the addon."
    end
    if (data.hidden or 0) > 0 then
        note = note .. (" %d left out by officers."):format(data.hidden)
    end
    if (data.flagged or 0) > 0 then
        note = note .. (" %d left out because their numbers are out of range (an edited addon, or a bug: tell the author)."):format(data.flagged)
    end
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", 0, -y)
    self.note:SetWidth(width)
    self.note:SetText(note)
    self.content:SetSize(width, y + self.note:GetStringHeight() + 8)
end
