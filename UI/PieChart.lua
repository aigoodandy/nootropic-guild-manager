--[[
    Nootropic Guild Manager - Pie chart
    The game has no drawing tools, so the slices are cooldown sweeps (the
    shrinking wedge on a recharging button) stopped at a fixed size, with a
    round texture. Each sweep covers from 12 o'clock to the end of its slice;
    the first slice sits on top, so every slice shows only its own wedge. The
    last slice is a plain circle at the bottom.

    local pie = W.PieChart(parent, size)
    pie:SetSlices({ { value, r, g, b }, ... })
    pie:SetHighlight(index or nil)       -- brightens one slice, dims the rest
    pie.OnSliceEnter = function(pie, index or nil) end   -- hover, nil = left it
]]
local _, ns = ...
local W = ns.Widgets

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SPAN = 1e7 -- a cooldown this long looks frozen (it would take months to move visibly)

local function NewSweep(pie)
    local cd = CreateFrame("Cooldown", nil, pie)
    cd:SetAllPoints()
    if cd.SetSwipeTexture then cd:SetSwipeTexture(CIRCLE) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd.noCooldownCount = true -- cooldown-text addons leave it alone
    cd:SetReverse(true)       -- draw the part from 12 o'clock to the end
    cd:EnableMouse(false)
    return cd
end

local function Shade(r, g, b, mode)
    if mode == "hi" then
        return r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
    elseif mode == "dim" then
        return r * 0.4, g * 0.4, b * 0.4
    end
    return r, g, b
end

function W.PieChart(parent, size)
    local pie = CreateFrame("Frame", nil, parent)
    pie:SetSize(size, size)
    pie:EnableMouse(true)

    -- thin dark outline
    pie.Ring = pie:CreateTexture(nil, "BACKGROUND")
    pie.Ring:SetTexture(CIRCLE)
    pie.Ring:SetPoint("TOPLEFT", -2, 2)
    pie.Ring:SetPoint("BOTTOMRIGHT", 2, -2)
    pie.Ring:SetVertexColor(0, 0, 0, 0.9)
    -- the last slice (and the empty pie)
    pie.Base = pie:CreateTexture(nil, "ARTWORK")
    pie.Base:SetTexture(CIRCLE)
    pie.Base:SetAllPoints()

    pie.sweeps = {}
    pie.slices = {}

    function pie:Paint()
        local n, hi = #self.slices, self.highlight
        for i, s in ipairs(self.slices) do
            local mode = hi and (i == hi and "hi" or "dim") or nil
            local r, g, b = Shade(s.r, s.g, s.b, mode)
            if i == n then
                self.Base:SetVertexColor(r, g, b, 1)
            else
                self.sweeps[i]:SetSwipeColor(r, g, b, 1)
            end
        end
        if n == 0 then self.Base:SetVertexColor(0.2, 0.2, 0.2, 1) end
    end

    -- slices: { { value, r, g, b }, ... }; empty ones are left out.
    function pie:SetSlices(list)
        local total = 0
        for _, s in ipairs(list) do total = total + math.max(0, s[1] or 0) end
        wipe(self.slices)
        local cum = 0
        for i, s in ipairs(list) do
            local v = math.max(0, s[1] or 0)
            if v > 0 then
                cum = cum + v / total
                self.slices[#self.slices + 1] = { index = i, to = math.min(1, cum), r = s[2], g = s[3], b = s[4] }
            end
        end
        local n = #self.slices
        if n > 0 then self.slices[n].to = 1 end
        local base = self:GetFrameLevel()
        for i = 1, math.max(n - 1, #self.sweeps) do
            local cd = self.sweeps[i]
            if i <= n - 1 then
                if not cd then
                    cd = NewSweep(self)
                    self.sweeps[i] = cd
                end
                cd:SetFrameLevel(base + n - i) -- first slice on top
                cd:SetCooldown(GetTime() - self.slices[i].to * SPAN, SPAN)
                cd:Show()
            elseif cd then
                cd:Hide()
            end
        end
        if self.highlight and not self:SliceFor(self.highlight) then self.highlight = nil end
        self:Paint()
    end

    -- Slice position for a data index (SetSlices' list index), or nil.
    function pie:SliceFor(index)
        for i, s in ipairs(self.slices) do if s.index == index then return i end end
    end

    -- Highlights the slice for a data index (nil = none).
    function pie:SetHighlight(index)
        local i = index and self:SliceFor(index)
        if self.highlight == i then return end
        self.highlight = i
        self:Paint()
    end

    -- The data index under the cursor, or nil.
    function pie:IndexAtCursor()
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local cx, cy = self:GetCenter()
        if not cx then return nil end
        local dx, dy = x / scale - cx, y / scale - cy
        local radius = self:GetWidth() / 2
        if dx * dx + dy * dy > radius * radius then return nil end
        local a = math.atan2(dx, dy) -- 0 at 12 o'clock, growing clockwise
        if a < 0 then a = a + 2 * math.pi end
        local frac = a / (2 * math.pi)
        for _, s in ipairs(self.slices) do
            if frac <= s.to then return s.index end
        end
    end

    local hovered
    local function Track()
        local index = pie:IndexAtCursor()
        if index ~= hovered then
            hovered = index
            if pie.OnSliceEnter then pie:OnSliceEnter(index) end
        end
    end
    pie:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", Track) end)
    pie:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        hovered = nil
        if self.OnSliceEnter then self:OnSliceEnter(nil) end
    end)

    pie:SetSlices({})
    return pie
end
