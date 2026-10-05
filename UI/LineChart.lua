--[[
    Nootropic Guild Manager - Line chart (a goal's progress over time)
    W.LineChart(parent, height): a plot with grid lines and their numbers on
    the left, dates along the bottom, a line through the points with a dot
    on each, and optional dashed lines (a target, a pace). Hovering shows the
    nearest point's tooltip.
      chart:SetData({
          points = { { x = n, y = n }, ... },   -- in x order
          xMin, xMax, yMax,                     -- the ranges shown (yMax is rounded up)
          color = { r, g, b },
          target = n,                           -- a dashed line across, labeled
          pace = { x1, y1, x2, y2 },            -- a faint dashed line
          xLabel = function(x) return text end,
          tip = function(point) return title, line, ... end,
      })
]]
local _, ns = ...
local W = ns.Widgets

local PAD_LEFT, PAD_BOTTOM, PAD_TOP, PAD_RIGHT = 34, 20, 10, 12 -- room for the numbers and dates
local GRID = 4 -- spaces between grid lines
local DOT = 7

-- Rounds a top value up to a whole step per grid line: 1, 2, 2.5, 5 x 10^n.
local function NiceMax(v)
    local raw = math.max(1, v) / GRID
    local mag = 10 ^ math.floor(math.log10(raw))
    local step = mag * 10
    for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
        if m * mag >= raw then step = m * mag break end
    end
    return math.max(1, math.ceil(step)) * GRID
end

function W.LineChart(parent, height)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetHeight(height)
    f:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)

    local plot = CreateFrame("Frame", nil, f)
    plot:SetPoint("TOPLEFT", PAD_LEFT, -PAD_TOP)
    plot:SetPoint("BOTTOMRIGHT", -PAD_RIGHT, PAD_BOTTOM)
    f.plot = plot

    f.Empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.Empty:SetPoint("CENTER", plot, "CENTER")
    if not plot.CreateLine then f.Empty:SetText("Line charts need a newer game client.") end

    -- pools, reused on every draw
    local pools = { line = {}, tex = {}, dot = {}, text = {} }
    local used = { line = 0, tex = 0, dot = 0, text = 0 }
    local function Take(kind)
        used[kind] = used[kind] + 1
        local o = pools[kind][used[kind]]
        if not o then
            if kind == "line" then
                o = plot:CreateLine(nil, "ARTWORK")
            elseif kind == "tex" then
                o = plot:CreateTexture(nil, "BACKGROUND")
            elseif kind == "dot" then
                o = plot:CreateTexture(nil, "OVERLAY")
                o:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                o:SetSize(DOT, DOT)
            else
                o = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            end
            pools[kind][used[kind]] = o
        end
        o:ClearAllPoints()
        o:Show()
        return o
    end
    local function HideAll()
        for kind, list in pairs(pools) do
            for _, o in ipairs(list) do o:Hide() end
            used[kind] = 0
        end
    end

    local function Segment(x1, y1, x2, y2, r, g, b, a, thick)
        local ln = Take("line")
        ln:SetThickness(thick or 2)
        ln:SetColorTexture(r, g, b, a or 1)
        ln:SetStartPoint("BOTTOMLEFT", plot, x1, y1)
        ln:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
        return ln
    end

    -- dashes of `on` pixels with `off` gaps
    local function Dashed(x1, y1, x2, y2, r, g, b, a, on, off)
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then return end
        on, off = on or 6, off or 4
        local pos = 0
        while pos < len do
            local e = math.min(len, pos + on)
            Segment(x1 + dx * pos / len, y1 + dy * pos / len, x1 + dx * e / len, y1 + dy * e / len, r, g, b, a, 1)
            pos = e + off
        end
    end

    -- the hover ring
    local ring = plot:CreateTexture(nil, "OVERLAY", nil, 2)
    ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    ring:SetSize(DOT + 5, DOT + 5)
    ring:SetVertexColor(1, 1, 1, 0.9)
    ring:Hide()

    function f:Draw()
        HideAll()
        ring:Hide()
        self.placed = {}
        local d = self.data
        if not d or not plot.CreateLine then return end
        local w, h = plot:GetWidth(), plot:GetHeight()
        if not w or w <= 0 or not h or h <= 0 then return end
        local xMin = d.xMin
        local xMax = math.max(d.xMax, xMin + 1)
        local yMax = NiceMax(math.max(d.yMax or 0, d.target or 0))
        self.yMax = yMax
        local function X(x) return (x - xMin) / (xMax - xMin) * w end
        local function Y(y) return math.min(h, y / yMax * h) end

        -- grid lines and their numbers
        for i = 0, GRID do
            local v = yMax * i / GRID
            local t = Take("tex")
            t:SetColorTexture(1, 1, 1, i == 0 and 0.25 or 0.07)
            t:SetHeight(1)
            t:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v))
            t:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, Y(v))
            local fs = Take("text")
            fs:SetText(v == math.floor(v) and tostring(v) or ("%.1f"):format(v))
            fs:SetPoint("RIGHT", plot, "BOTTOMLEFT", -5, Y(v))
        end

        -- dates: first, last, and the middle when there's room
        if d.xLabel then
            local first = Take("text")
            first:SetText(d.xLabel(xMin))
            first:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -4)
            local last = Take("text")
            last:SetText(d.xLabel(xMax))
            last:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -4)
            if w > 220 and xMax - xMin >= 2 then
                local mid = math.floor((xMin + xMax) / 2 + 0.5)
                local fs = Take("text")
                fs:SetText(d.xLabel(mid))
                fs:SetPoint("TOP", plot, "BOTTOMLEFT", X(mid), -4)
            end
        end

        -- the pace (where the count would be, rising steadily to the target)
        if d.pace then
            local p = d.pace
            Dashed(X(p[1]), Y(p[2]), X(p[3]), Y(p[4]), 0.6, 0.8, 1, 0.45, 3, 4)
        end
        -- the target
        if d.target then
            local y = Y(d.target)
            Dashed(0, y, w, y, 1, 0.4, 0.35, 0.8)
            local fs = Take("text")
            fs:SetText(("|cffff7766Target %d|r"):format(d.target))
            fs:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 4, y + 2)
        end

        -- the line and its dots
        local r, g, b = unpack(d.color or { 1, 0.82, 0 })
        local prevX, prevY
        for i, pt in ipairs(d.points or {}) do
            local x, y = X(pt.x), Y(pt.y)
            if prevX then Segment(prevX, prevY, x, y, r, g, b, 1, 2) end
            local dot = Take("dot")
            dot:SetVertexColor(r, g, b, 1)
            dot:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
            self.placed[i] = { x = x, y = y, point = pt }
            prevX, prevY = x, y
        end
    end

    function f:SetData(data)
        self.data = data
        self.hover = nil
        self:Draw()
    end

    plot:SetScript("OnSizeChanged", function() f:Draw() end)

    -- hovering: the nearest point (by x) gets a ring and a tooltip
    local function Hover()
        local placed = f.placed
        if not placed or #placed == 0 or not plot:GetLeft() then return end
        local cx = GetCursorPosition() / plot:GetEffectiveScale() - plot:GetLeft()
        local best, bestDist
        for i, p in ipairs(placed) do
            local dist = math.abs(p.x - cx)
            if not bestDist or dist < bestDist then best, bestDist = i, dist end
        end
        if best == f.hover then return end
        f.hover = best
        local p = placed[best]
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y)
        ring:Show()
        if f.data.tip then
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            local lines = { f.data.tip(p.point) }
            for i, text in ipairs(lines) do
                if i == 1 then GameTooltip:AddLine(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        self.hover = nil
        self:SetScript("OnUpdate", Hover)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.hover = nil
        ring:Hide()
        GameTooltip:Hide()
    end)

    return f
end
