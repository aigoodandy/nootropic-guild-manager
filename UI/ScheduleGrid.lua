--[[
    Nootropic Guild Manager - Week grid (usually online)
    7 days x 12 two-hour blocks. Read-only (a heatmap) or editable: click a
    block to toggle it, drag to paint several, click a day name to copy that
    day to the other weekdays (or the other weekend day).

      local grid = ns.ScheduleGrid.New(parent, { editable = true, cell = 16,
          onChange = function(bits) end, onHover = function(day, block) end })
      grid:SetBits(bits)   -- hour index (0 = Monday 00:00) -> true
      grid:GetBits()
]]
local _, ns = ...
local SG = {}
SG.__index = SG
ns.ScheduleGrid = SG

local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local LABELS = { [0] = "12a", [3] = "6a", [6] = "12p", [9] = "6p" }
local LABEL_W = 30
local ON = { 0.16, 0.62, 0.42 }
local OFF = { 0.05, 0.04, 0.03 }

function SG.New(parent, opts)
    opts = opts or {}
    local self = setmetatable({ bits = {}, opts = opts, cells = {} }, SG)
    local cw = opts.cell or 14
    local ch = opts.cellH or math.max(10, cw - 3)
    local gap = 2
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(LABEL_W + 12 * (cw + gap), 12 + 7 * (ch + gap))
    self.frame = f

    for b, text in pairs(LABELS) do
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        l:SetPoint("TOPLEFT", LABEL_W + b * (cw + gap), 0)
        l:SetText(text)
    end

    for d = 0, 6 do
        local y = -12 - d * (ch + gap)
        local day = CreateFrame("Button", nil, f)
        day:SetSize(LABEL_W - 2, ch)
        day:SetPoint("TOPLEFT", 0, y)
        day.Text = day:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        day.Text:SetPoint("LEFT", 0, 0)
        day.Text:SetText(DAYS[d + 1])
        if opts.editable then
            day:SetScript("OnClick", function() self:CopyDay(d) end)
            day:SetScript("OnEnter", function(b)
                b.Text:SetTextColor(1, 0.82, 0)
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                GameTooltip:AddLine(("Copy %s"):format(DAYS[d + 1]))
                GameTooltip:AddLine(d < 5 and "Copies this day to every weekday." or "Copies this day to the other weekend day.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            day:SetScript("OnLeave", function(b) b.Text:SetTextColor(1, 1, 1); GameTooltip:Hide() end)
        else
            day:EnableMouse(false)
        end
        for b = 0, 11 do
            local cell = CreateFrame("Button", nil, f, "BackdropTemplate")
            cell:SetSize(cw, ch)
            cell:SetPoint("TOPLEFT", LABEL_W + b * (cw + gap), y)
            cell:SetBackdrop({ bgFile = ns.Widgets.WHITE, edgeFile = ns.Widgets.WHITE, edgeSize = 1 })
            cell.day, cell.block = d, b
            cell:SetScript("OnMouseDown", function(c)
                if not opts.editable then return end
                self.painting = true
                self.paintValue = not self:Block(c.day, c.block)
                self:SetBlock(c.day, c.block, self.paintValue)
                -- the pressed block keeps the mouse while dragging, so look
                -- for the block under the cursor every frame instead
                f:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then self:StopPaint() return end
                    for _, other in pairs(self.cells) do
                        if other:IsMouseOver() and self:Block(other.day, other.block) ~= self.paintValue then
                            self:SetBlock(other.day, other.block, self.paintValue)
                        end
                    end
                end)
            end)
            cell:SetScript("OnMouseUp", function() self:StopPaint() end)
            cell:SetScript("OnEnter", function(c)
                c:SetBackdropBorderColor(1, 0.82, 0, 1)
                if opts.onHover then opts.onHover(c, c.day, c.block) end
            end)
            cell:SetScript("OnLeave", function(c)
                self:Paint(c)
                GameTooltip:Hide()
            end)
            if not opts.editable and not opts.onHover then cell:EnableMouse(false) end
            self.cells[d * 12 + b] = cell
        end
    end
    f:SetScript("OnHide", function() self:StopPaint() end)
    self:Redraw()
    return self
end

function SG:StopPaint()
    self.frame:SetScript("OnUpdate", nil)
    if self.painting then
        self.painting = false
        if self.opts.onChange then self.opts.onChange(self.bits) end
    end
end

function SG:Block(day, block)
    local h = day * 24 + block * 2
    return self.bits[h] or self.bits[h + 1] or false
end

function SG:SetBlock(day, block, on)
    local h = day * 24 + block * 2
    self.bits[h], self.bits[h + 1] = on or nil, on or nil
    self:Paint(self.cells[day * 12 + block])
end

function SG:Paint(cell)
    local on = self:Block(cell.day, cell.block)
    local c = on and ON or OFF
    cell:SetBackdropColor(c[1], c[2], c[3], 1)
    if on then cell:SetBackdropBorderColor(0.36, 0.79, 0.65, 1) else cell:SetBackdropBorderColor(0.2, 0.18, 0.14, 1) end
end

function SG:Redraw()
    for _, cell in pairs(self.cells) do self:Paint(cell) end
end

function SG:SetBits(bits)
    self.bits = {}
    for h, v in pairs(bits or {}) do if v then self.bits[h] = true end end
    self:Redraw()
end

function SG:GetBits() return self.bits end

-- Copies a day to the other weekdays (Mon-Fri) or the other weekend day.
function SG:CopyDay(d)
    local first, last = 0, 4
    if d >= 5 then first, last = 5, 6 end
    for other = first, last do
        if other ~= d then
            for h = 0, 23 do self.bits[other * 24 + h] = self.bits[d * 24 + h] or nil end
        end
    end
    self:Redraw()
    if self.opts.onChange then self.opts.onChange(self.bits) end
end

-- Presets: "evenings" (weekdays 6 pm-12 am), "weekends" (Sat-Sun noon-12 am), "clear".
function SG:Preset(kind)
    if kind == "clear" then
        self.bits = {}
    elseif kind == "evenings" then
        for d = 0, 4 do for h = 18, 23 do self.bits[d * 24 + h] = true end end
    elseif kind == "weekends" then
        for d = 5, 6 do for h = 12, 23 do self.bits[d * 24 + h] = true end end
    end
    self:Redraw()
    if self.opts.onChange then self.opts.onChange(self.bits) end
end
