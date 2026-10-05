--[[
    Nootropic Guild Manager - Chart layouts (Insights tab)
    How a poll's or stat's results are drawn. The Insights page (UI/PollsView.lua)
    draws the two bar layouts itself; this file draws the others:

      barspie   bars with names above, and a pie under them (the page's own)
      bars      bars only (the page's own)
      pie       a big pie with a legend under it
      columns   upright bars side by side, names underneath
      number    one big headline figure (the first row), the rest listed small

    Every layout keeps each row's color and icon, lights up with the pie when
    hovered, and clicks through (a vote, or the roster) like the bars.

    An item: { label, count, pct (0-100), r, g, b, look (icon/classFile),
               voted (your vote), share (0-1, its part of the total) }
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local CL = {}
ns.ChartLayouts = CL

CL.LAYOUTS = {
    { key = "barspie", label = "Bars and pie" },
    { key = "bars",    label = "Bars only" },
    { key = "pie",     label = "Pie with legend" },
    { key = "columns", label = "Columns" },
    { key = "number",  label = "Big number" },
}

function CL.Label(key)
    for _, l in ipairs(CL.LAYOUTS) do if l.key == key then return l.label end end
    return CL.LAYOUTS[1].label
end

-- Does the page draw this layout itself (bars), or this file?
function CL.UsesBars(key)
    return key == nil or key == "barspie" or key == "bars"
end

local MAX_ITEMS = 30
local LEGEND_H = 22
local COL_AREA_H = 150 -- the tallest column
local COL_LABEL_H = 28
local PIE_BIG = 220

-- Shows a row's icon (its chosen one, or a class icon) on a texture, or hides it.
local function SetIcon(tex, look)
    if look and look.icon then
        W.SetIcon(tex, look.icon)
    elseif look and look.classFile then
        W.SetClassIcon(tex, look.classFile)
    else
        tex:Hide()
        return false
    end
    tex:Show()
    return true
end

local function Hoverable(b, index)
    b.index = index
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:GetHighlightTexture():SetAlpha(0.3)
    b:SetScript("OnEnter", function(self) ns.PollsView:HoverResult(self.index, "row") end)
    b:SetScript("OnLeave", function() ns.PollsView:HoverResult(nil, "row") end)
    b:SetScript("OnClick", function(self) if CL.onClick then CL.onClick(self.index) end end)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function CL:Build(content)
    self.content = content

    -- legend lines (under the big pie, and the small lines of Big number)
    self.legend = {}
    for i = 1, MAX_ITEMS do
        local b = CreateFrame("Button", nil, content)
        b:SetHeight(LEGEND_H)
        Hoverable(b, i)
        b.Swatch = b:CreateTexture(nil, "ARTWORK")
        b.Swatch:SetSize(12, 12)
        b.Swatch:SetPoint("LEFT", 4, 0)
        b.Swatch:SetColorTexture(1, 1, 1)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetSize(16, 16)
        b.Icon:SetPoint("LEFT", b.Swatch, "RIGHT", 6, 0)
        b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Label:SetJustifyH("LEFT")
        b.Label:SetWordWrap(false)
        b.Count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Count:SetPoint("RIGHT", -4, 0)
        b.Label:SetPoint("RIGHT", b.Count, "LEFT", -8, 0)
        b:Hide()
        self.legend[i] = b
    end

    -- columns
    local cols = CreateFrame("Frame", nil, content)
    cols:SetHeight(COL_AREA_H + COL_LABEL_H + 18)
    cols:Hide()
    self.colArea = cols
    self.columns = {}
    for i = 1, MAX_ITEMS do
        local b = CreateFrame("Button", nil, cols)
        b:SetHeight(COL_AREA_H + COL_LABEL_H + 18)
        Hoverable(b, i)
        local bg = CreateFrame("Frame", nil, b, "BackdropTemplate")
        bg:SetPoint("BOTTOMLEFT", 0, COL_LABEL_H)
        bg:SetPoint("BOTTOMRIGHT", 0, COL_LABEL_H)
        bg:SetHeight(COL_AREA_H)
        bg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        bg:SetBackdropColor(0, 0, 0, 0.45)
        bg:SetBackdropBorderColor(0.55, 0.47, 0.3, 1)
        local bar = CreateFrame("StatusBar", nil, bg)
        bar:SetPoint("TOPLEFT", 3, -3)
        bar:SetPoint("BOTTOMRIGHT", -3, 3)
        bar:SetOrientation("VERTICAL")
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, 1)
        b.Bar = bar
        b.Count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Count:SetPoint("BOTTOM", bg, "TOP", 0, 3)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetSize(14, 14)
        b.Icon:SetPoint("TOP", bg, "BOTTOM", 0, -3)
        b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Label:SetPoint("TOP", b.Icon, "BOTTOM", 0, -1)
        b.Label:SetWordWrap(false)
        b:Hide()
        self.columns[i] = b
    end

    -- big number
    local num = CreateFrame("Button", nil, content)
    num:SetHeight(84)
    Hoverable(num, 1)
    num.Value = num:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    num.Value:SetPoint("TOPLEFT", 4, -4)
    num.Icon = num:CreateTexture(nil, "ARTWORK")
    num.Icon:SetSize(22, 22)
    num.Icon:SetPoint("LEFT", num.Value, "RIGHT", 12, 0)
    num.Label = num:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    num.Label:SetPoint("LEFT", num.Icon, "RIGHT", 6, 0)
    num.Label:SetPoint("RIGHT", -4, 0)
    num.Label:SetJustifyH("LEFT")
    num.Label:SetWordWrap(false)
    num.Sub = num:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    num.Sub:SetPoint("TOPLEFT", num.Value, "BOTTOMLEFT", 0, -4)
    num.BarBg = W.StatBar(num, 16)
    num.BarBg:SetPoint("BOTTOMLEFT", 0, 4)
    num.BarBg:SetPoint("BOTTOMRIGHT", 0, 4)
    num:Hide()
    self.number = num
end

function CL:HideAll()
    for _, b in ipairs(self.legend) do b:Hide() end
    self.colArea:Hide()
    self.number:Hide()
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------
-- Draws `layout` under `anchor` (the page's status line). items: see the top.
-- opts: { onClick = function(index), noun = "members", barTargets = {},
--         pie = the page's pie }. Returns the lowest piece (for the footer)
-- and the frames hovering lights up (by item number).
function CL:Draw(layout, items, opts, anchor)
    self:HideAll()
    self.onClick = opts.onClick
    local c = self.content
    local hover = {}
    local n = math.min(#items, MAX_ITEMS)

    if layout == "pie" then
        local pie = opts.pie
        local size = math.floor(math.min(PIE_BIG, (c:GetWidth() or 300) - 60))
        pie:ClearAllPoints()
        pie:SetSize(size, size)
        -- the status line spans the page, so this centers the pie
        pie:SetPoint("TOP", anchor, "BOTTOM", 0, -14)
        pie:Show()
        local prev = pie
        for i = 1, n do
            local b, it = self.legend[i], items[i]
            b.index = i
            self:FillLegend(b, it)
            b:ClearAllPoints()
            b:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -12 or -2)
            b:SetPoint("LEFT", c, "LEFT", 14, 0)
            b:SetPoint("RIGHT", c, "RIGHT", -14, 0)
            b:Show()
            hover[i] = b
            prev = b
        end
        return prev, hover
    end

    opts.pie:Hide()

    if layout == "columns" then
        local area = self.colArea
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
        area:SetPoint("RIGHT", c, "RIGHT", -14, 0)
        area:Show()
        local width = math.max(100, (c:GetWidth() or 300) - 28)
        local slot = width / math.max(1, n)
        local colW = math.max(14, math.min(56, slot - 8))
        local most = 0
        for i = 1, n do most = math.max(most, items[i].count) end
        for i = 1, n do
            local b, it = self.columns[i], items[i]
            b:SetWidth(colW)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", (i - 1) * slot + (slot - colW) / 2, 0)
            b.Bar:SetStatusBarColor(it.r, it.g, it.b)
            local target = most > 0 and it.count / most or 0
            opts.barTargets[b.Bar] = target
            b.Bar:SetValue(target)
            b.Count:SetText(it.count)
            local hasIcon = SetIcon(b.Icon, it.look)
            b.Label:ClearAllPoints()
            b.Label:SetPoint("TOP", hasIcon and b.Icon or b.Bar:GetParent(), "BOTTOM", 0, hasIcon and -1 or -3)
            b.Label:SetWidth(slot - 2)
            b.Label:SetText(it.label)
            b.Label:SetTextColor(it.r, it.g, it.b)
            b:Show()
            hover[i] = b
        end
        for i = n + 1, MAX_ITEMS do self.columns[i]:Hide() end
        return area, hover
    end

    if layout == "number" then
        local num, first = self.number, items[1]
        num:ClearAllPoints()
        num:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
        num:SetPoint("RIGHT", c, "RIGHT", -14, 0)
        num:Show()
        hover[1] = num
        local prev = num
        if first then
            num.Value:SetText(("%d%%"):format(first.pct))
            num.Value:SetTextColor(first.r, first.g, first.b)
            SetIcon(num.Icon, first.look)
            num.Icon:ClearAllPoints()
            num.Icon:SetPoint("LEFT", num.Value, "RIGHT", 12, 0)
            num.Label:ClearAllPoints()
            num.Label:SetPoint("LEFT", num.Icon:IsShown() and num.Icon or num.Value, "RIGHT", num.Icon:IsShown() and 6 or 12, 0)
            num.Label:SetPoint("RIGHT", -4, 0)
            num.Label:SetText(first.label .. (first.voted and "  |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t" or ""))
            num.Sub:SetText(("%d of %d %s"):format(first.count, opts.total or 0, opts.noun or "members"))
            local bar = num.BarBg.Bar
            bar:SetStatusBarColor(first.r, first.g, first.b)
            opts.barTargets[bar] = first.share or 0
            bar:SetValue(first.share or 0)
        else
            num.Value:SetText("-")
            num.Label:SetText("Nothing yet")
            num.Sub:SetText("")
        end
        -- the other rows, small
        for i = 2, n do
            local b = self.legend[i - 1]
            self:FillLegend(b, items[i])
            b.index = i
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 2 and -10 or -2)
            b:SetPoint("RIGHT", c, "RIGHT", -14, 0)
            b:Show()
            hover[i] = b
            prev = b
        end
        return prev, hover
    end
end

function CL:FillLegend(b, it)
    b.Swatch:SetVertexColor(it.r, it.g, it.b)
    local hasIcon = SetIcon(b.Icon, it.look)
    b.Label:ClearAllPoints()
    b.Label:SetPoint("LEFT", hasIcon and b.Icon or b.Swatch, "RIGHT", 6, 0)
    b.Label:SetPoint("RIGHT", b.Count, "LEFT", -8, 0)
    b.Label:SetText(it.label .. (it.voted and "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" or ""))
    b.Label:SetTextColor(it.r, it.g, it.b)
    b.Count:SetText(("%d  |cff9d9d9d%d%%|r"):format(it.count, it.pct))
end
