--[[
    Nootropic Guild Manager - Overview tab (everyone)
    The guild at a glance, for the members active in a chosen window
    (Settings().overviewDays: 7, 30, 90 or 0 = everyone):

      Classes         how many of each class
      Levels          level bands (1-9 ... 50-59, 60)
      Professions     how many have each profession
      When we play    a week heatmap from the hours guildmates share
                      ("Learn when I usually play"), in your clock

    People are counted once, as their main, unless "Count alts" is on
    (Settings().overviewAlts). A person counts as active if any of their
    characters was online in the window. Clicking a bar opens Find with that
    search.
]]
local _, ns = ...
local W = ns.Widgets
local D = ns.Data
local OV = {}
ns.OverviewView = OV

local GRAY = "|cff9d9d9d"
local FAINT = "|cff6e6e6e"
local WINDOWS = { 7, 30, 90, 0 }
local BAR_H, BAR_GAP = 20, 3
-- each section as the dashboard's: a heading with a dashed rule, then a box
local HEAD, PAD, EDGE = 26, 14, 4
local IN_X, IN_Y = EDGE + PAD, HEAD + EDGE + PAD -- where a box's content starts
local BELOW = PAD + EDGE + 4                     -- room under a box's content
local COUNT_W = 62 -- room right of the bar for "11  44%"
local LEVEL_BANDS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 59 }, { 60, 60 } }
local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

function OV:Days()
    local d = ns.DB:Settings().overviewDays
    if d == nil then return 30 end
    return d
end

local function WindowText(d)
    return d == 0 and "Everyone" or ("Active in " .. d .. " days")
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function Active(e, days)
    if days == 0 or e.online then return true end
    return (e.lastOnline or 0) <= days * 24
end

-- People (or characters, with alts counted) active in the window:
-- { { e = entry shown, chars = { entries } } ... }
-- days/alts: the view's own filter unless given (the NGM Peon code always
-- counts the default view: active in 30 days, a player's characters once)
function OV:People(days, alts)
    if days == nil then days = self:Days() end
    if alts == nil then alts = ns.DB:Settings().overviewAlts end
    local out = {}
    if alts then
        for _, e in ipairs(ns.Roster.members) do
            if Active(e, days) then out[#out + 1] = { e = e, chars = { e } } end
        end
        return out
    end
    local groups, order = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        local key = e.main or e.full
        local g = groups[key]
        if not g then
            g = { chars = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        g.chars[#g.chars + 1] = e
        if e.full == key then g.e = e end
    end
    for _, key in ipairs(order) do
        local g = groups[key]
        g.e = g.e or g.chars[1] -- main not in the guild: their first alt
        local active = false
        for _, c in ipairs(g.chars) do if Active(c, days) then active = true break end end
        if active then out[#out + 1] = g end
    end
    return out
end

function OV:Census(days, alts)
    local people = self:People(days, alts)
    local classes, levels, profs = {}, {}, {}
    local heat, heatNames, sharing = {}, {}, 0
    for _, p in ipairs(people) do
        local e = p.e
        classes[e.classFile] = (classes[e.classFile] or 0) + 1
        for i, band in ipairs(LEVEL_BANDS) do
            if (e.level or 0) >= band[1] and (e.level or 0) <= band[2] then levels[i] = (levels[i] or 0) + 1 end
        end
        local has, hours = {}, nil
        for _, c in ipairs(p.chars) do
            for _, pr in ipairs(c.profs or {}) do has[pr.name] = true end
            local bits = ns.Profile:Hours(c.full)
            if bits then
                hours = hours or {}
                for h, on in pairs(bits) do if on then hours[h] = true end end
            end
        end
        for name in pairs(has) do profs[name] = (profs[name] or 0) + 1 end
        if hours then
            sharing = sharing + 1
            for d = 0, 6 do
                for b = 0, 11 do
                    if hours[d * 24 + b * 2] or hours[d * 24 + b * 2 + 1] then
                        local k = d * 12 + b
                        heat[k] = (heat[k] or 0) + 1
                        heatNames[k] = heatNames[k] or {}
                        table.insert(heatNames[k], e)
                    end
                end
            end
        end
    end
    local heatMax = 0
    for _, n in pairs(heat) do if n > heatMax then heatMax = n end end
    return { people = #people, classes = classes, levels = levels, profs = profs,
             heat = heat, heatNames = heatNames, heatMax = heatMax, sharing = sharing }
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function ClassName(file)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file])
        or (file:sub(1, 1) .. file:sub(2):lower())
end

-- A section, as the dashboard's: an upper-case heading and a dashed rule,
-- then a box (dark fill, notched edge) holding it. Placed by Layout().
local function Section(parent, title)
    local T = ns.Theme
    local s = CreateFrame("Frame", nil, parent)
    s.Title = s:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    s.Title:SetPoint("TOPLEFT", 0, -2)
    T:Ink(s.Title, T.C.fg)
    s.Title:SetText(T.Upper(title))
    s.Sub = s:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    s.Sub:SetPoint("LEFT", s.Title, "RIGHT", 8, 0)
    s.Rule = T:Dashes(s)
    s.Rule:SetPoint("LEFT", s.Sub, "RIGHT", 10, 0)
    s.Rule:SetPoint("RIGHT", s, "RIGHT", -EDGE, 0)
    s.Box = CreateFrame("Frame", nil, s)
    s.Box:SetPoint("TOPLEFT", EDGE, -(HEAD + EDGE))
    s.Box:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    s.Box:SetFrameLevel(s:GetFrameLevel())
    T:Box(s.Box, T.C.bg1, T.C.edge, EDGE)
    s.bars = {}
    return s
end

-- One clickable bar: icon, label, the bar itself and the count.
local function Bar(section)
    local b = CreateFrame("Button", nil, section)
    b:SetHeight(BAR_H)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetSize(16, 16)
    b.Icon:SetPoint("LEFT", 2, 0)
    b.Label = b:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    b.Label:SetPoint("LEFT", b.Icon, "RIGHT", 6, 0)
    b.Label:SetWidth(96)
    b.Label:SetJustifyH("LEFT")
    b.Label:SetWordWrap(false)
    b.Track = b:CreateTexture(nil, "BACKGROUND")
    b.Track:SetPoint("LEFT", b.Label, "RIGHT", 6, 0)
    b.Track:SetPoint("RIGHT", -COUNT_W, 0)
    -- as the dashboard's bars: a 14-unit track in the line colour
    b.Track:SetHeight(14)
    local line = ns.Theme.C.line
    ns.Theme:Paint(b.Track, line)
    b.Fill = b:CreateTexture(nil, "ARTWORK")
    b.Fill:SetPoint("LEFT", b.Track, "LEFT", 0, 0)
    b.Fill:SetHeight(14)
    b.Count = b:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    b.Count:SetPoint("RIGHT", -4, 0)
    b.Count:SetJustifyH("RIGHT")
    b:SetScript("OnClick", function(self)
        if self.search then ns.UI:SetSearch(self.search) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tipTitle or "")
        if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
        GameTooltip:AddLine("Click to list them on the Find tab.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- rows: { { icon, label, n, color = {r,g,b}, search, tip } ... }
-- As the dashboard: each bar's length is its share of everyone counted;
-- classes in their colours, everything else yellow.
local function FillBars(section, rows, total, width)
    width = width - 2 * IN_X
    for i, r in ipairs(rows) do
        local b = section.bars[i] or Bar(section)
        section.bars[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", IN_X, -IN_Y - (i - 1) * (BAR_H + BAR_GAP))
        b:SetWidth(width)
        if r.classFile then W.SetClassIcon(b.Icon, r.classFile) else W.SetIcon(b.Icon, r.icon) end
        b.Label:SetText(r.label)
        local track = width - 2 - 16 - 6 - 96 - 6 - COUNT_W
        b.Fill:SetWidth(math.max(1, track * (total > 0 and r.n / total or 0)))
        b.Fill:SetShown(r.n > 0)
        local c = r.color or ns.Theme.C.yellow
        ns.Theme:Paint(b.Fill, c)
        local pct = total > 0 and math.floor(r.n / total * 100 + 0.5) or 0
        b.Count:SetText(r.n > 0 and (r.n .. FAINT .. "  " .. pct .. "%|r") or (FAINT .. "0|r"))
        b.search, b.tipTitle, b.tipText = r.search, r.label, r.tip
        b:Show()
    end
    for i = #rows + 1, #section.bars do section.bars[i]:Hide() end
    return IN_Y + #rows * (BAR_H + BAR_GAP) - BAR_GAP + BELOW
end

function OV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)

    local window = W.Button(page, "", 140, 22)
    window:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    window:SetScript("OnClick", function(btn)
        local items = { { text = "Count", isTitle = true } }
        for _, d in ipairs(WINDOWS) do
            items[#items + 1] = { text = WindowText(d), radio = true,
                checked = function() return OV:Days() == d end,
                func = function() ns.DB:Settings().overviewDays = d; OV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(window, "Who's counted", "Only members online in this many days (any of their characters), or everyone.")
    self.windowButton = window

    local alts = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    alts:SetSize(22, 22)
    alts:SetPoint("RIGHT", window, "LEFT", -110, 0)
    local label = alts.Text or alts.text or alts:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    label:ClearAllPoints()
    label:SetPoint("LEFT", alts, "RIGHT", 2, 1)
    label:SetFontObject("NGMFontTextSmall")
    label:SetText("Count alts")
    alts:SetScript("OnClick", function(cb)
        ns.DB:Settings().overviewAlts = cb:GetChecked() and true or nil
        OV:Refresh()
    end)
    W.Tooltip(alts, "Count alts", "Off: each person counts once, as their main. On: every character counts.")
    self.altsCheck = alts

    local inset = frame.Inset
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMOverviewScroll", page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    self.content = content

    self.classes = Section(content, "Classes")
    self.levels = Section(content, "Levels")
    self.profs = Section(content, "Professions")
    self.when = Section(content, "When we play")
    self.grid = ns.ScheduleGrid.New(self.when, { cell = 30, cellH = 20, onHover = function(cell, d, b) OV:ShowHeatTip(cell, d, b) end })
    self.grid.frame:SetPoint("TOPLEFT", IN_X, -IN_Y)
    self.whenNote = self.when:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.whenNote:SetPoint("TOPLEFT", self.grid.frame, "BOTTOMLEFT", 0, -6)
    self.whenNote:SetWordWrap(true)
    self.whenNote:SetJustifyH("LEFT")

    page:SetScript("OnShow", function()
        ns.Roster:Request()
        OV:Refresh()
    end)
    page:SetScript("OnSizeChanged", function() if page:IsVisible() then OV:Refresh() end end)
    ns:On("ROSTER_UPDATED", function() if page:IsVisible() then ns.Debounce("overview", 0.3, function() OV:Refresh() end) end end)
    ns:On("MEMBER_CHANGED", function() if page:IsVisible() then ns.Debounce("overview", 0.3, function() OV:Refresh() end) end end)
end

local function HourText(h) return ns.Profile.HourText(h) end

function OV:ShowHeatTip(cell, d, b)
    local c = self.census
    if not c then return end
    local k = d * 12 + b
    local n = c.heat[k] or 0
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s %s-%s"):format(DAYS[d + 1], HourText(b * 2), HourText(b * 2 + 2)))
    GameTooltip:AddLine(n == 1 and "1 usually plays then" or (n .. " usually play then"), 1, 1, 1)
    local names = c.heatNames[k] or {}
    table.sort(names, function(x, y) return x.short < y.short end)
    for i, e in ipairs(names) do
        if i > 15 then GameTooltip:AddLine(("...and %d more"):format(#names - 15), 0.6, 0.6, 0.6) break end
        local r, g, bl = ns.ClassColor(e.classFile)
        GameTooltip:AddLine(e.short .. (e.online and "  |cff20ff20online|r" or ""), r, g, bl)
    end
    GameTooltip:Show()
end

-- Places the sections in one or two columns, depending on the width.
function OV:Layout(width, heights)
    local two = width >= 820
    local colW = two and math.floor((width - 30) / 2) or width
    local order = { self.classes, self.levels, self.profs, self.when }
    local y = { 0, 0 }
    for i, s in ipairs(order) do
        local col = two and ((i - 1) % 2 + 1) or 1
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", (col - 1) * (colW + 30), -y[col])
        s:SetSize(colW, heights[s])
        y[col] = y[col] + heights[s] + 18
    end
    self.content:SetSize(width, math.max(y[1], y[2]))
    return colW
end

function OV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local c = self:Census()
    self.census = c
    local days = self:Days()
    self.windowButton:SetText(WindowText(days))
    self.altsCheck:SetChecked(ns.DB:Settings().overviewAlts and true or false)
    local who = ns.DB:Settings().overviewAlts and "characters" or "people"
    self.title:SetText(("Overview  " .. GRAY .. "- %d %s%s|r"):format(c.people, who,
        days > 0 and (" online in the last " .. days .. " days") or " in the guild"))

    local width = math.max(300, math.floor(self.scroll:GetWidth()))
    local colW = width >= 820 and math.floor((width - 30) / 2) or width

    local rows = {}
    for _, file in ipairs(D.CLASSES) do
        local r, g, b = ns.ClassColor(file)
        rows[#rows + 1] = { label = ClassName(file), n = c.classes[file] or 0, color = { r, g, b },
            classFile = file, search = "class:" .. ClassName(file):lower() }
    end
    local heights = {}
    heights[self.classes] = FillBars(self.classes, rows, c.people, colW)

    rows = {}
    for i, band in ipairs(LEVEL_BANDS) do
        local label = band[1] == band[2] and ("Level " .. band[1]) or (band[1] .. "-" .. band[2])
        rows[#rows + 1] = { label = label, n = c.levels[i] or 0, icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
            search = band[1] == band[2] and ("level=" .. band[1]) or ("level>=" .. band[1] .. " level<=" .. band[2]) }
    end
    heights[self.levels] = FillBars(self.levels, rows, c.people, colW)

    rows = {}
    for _, p in ipairs(D.PROFESSIONS) do
        rows[#rows + 1] = { label = p.name, n = c.profs[p.name] or 0, icon = p.icon,
            search = p.name:find(" ") and ('prof:"' .. p.name:lower() .. '"') or ("prof:" .. p.name:lower()),
            tip = "From their addon, or what's set on their profile for members without it." }
    end
    heights[self.profs] = FillBars(self.profs, rows, c.people, colW)

    self.grid:SetCounts(c.heat, c.heatMax)
    self.when.Sub:SetText(ns.Profile.ClockLabel and ("(" .. ns.Profile.ClockLabel() .. ")") or "")
    self.whenNote:SetWidth(colW - 2 * IN_X)
    self.whenNote:SetText(c.sharing == 0
        and "Nobody counted here shares their hours yet. Hours come from \"Learn when I usually play\" (Options > Sharing)."
        or (("%d of %d %s share their hours. Brighter means more of them usually play then. Hover a block for who."):format(c.sharing, c.people, who)))
    heights[self.when] = IN_Y + self.grid.frame:GetHeight() + 6 + math.max(14, self.whenNote:GetStringHeight()) + BELOW

    self:Layout(width, heights)
end
