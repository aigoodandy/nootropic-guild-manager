--[[
    Nootropic Guild Manager - Member picker
    A small searchable window for choosing a guild member (used to link
    mains and alts).

    ns.MemberPicker:Open{ title = "...", exclude = { [full] = true }, onPick = function(full) end }
]]
local _, ns = ...
local W = ns.Widgets
local MP = {}
ns.MemberPicker = MP

local ROW_H = 22

function MP:Build()
    local f = CreateFrame("Frame", "NootropicGMMemberPicker", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(280, 400)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f

    local search = CreateFrame("EditBox", "NootropicGMMemberPickerSearch", f, "SearchBoxTemplate")
    search:SetSize(250, 20)
    search:SetPoint("TOPLEFT", 16, -32)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText("Search characters...") end
    search:HookScript("OnTextChanged", function() MP:Refresh() end)
    search:HookScript("OnEnterPressed", function()
        local first = MP.results and MP.results[1]
        if first then MP:Pick(first.full) end
    end)
    self.search = search

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -60)
    scrollBox:SetPoint("BOTTOMRIGHT", -26, 10)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, e) MP:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.empty = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisable")
    self.empty:SetPoint("CENTER", scrollBox, "CENTER")
end

function MP:InitRow(row, e)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(16, 16)
        row.Icon:SetPoint("LEFT", 4, 0)
        row.Name = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
        row.Info = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
        row.Info:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function(self) MP:Pick(self.entry.full) end)
    end
    row.entry = e
    W.SetClassIcon(row.Icon, e.classFile)
    row.Name:SetText(e.short)
    row.Name:SetTextColor(ns.ClassColor(e.classFile))
    if e.isAlt then
        row.Info:SetText(("%d - alt of %s"):format(e.level, e.mainShort))
    elseif #e.alts > 0 then
        row.Info:SetText(("%d - main, %d alt%s"):format(e.level, #e.alts, #e.alts == 1 and "" or "s"))
    else
        row.Info:SetText(tostring(e.level))
    end
end

function MP:Refresh()
    local query = (self.search:GetText() or ""):lower()
    local exclude = self.opts and self.opts.exclude or {}
    local list = {}
    for _, e in ipairs(ns.Roster.members) do
        if not exclude[e.full] and (query == "" or e.search.name:find(query, 1, true)) then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b) return a.short < b.short end)
    self.results = list
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    self.empty:SetText(#list == 0 and "No matching characters." or "")
end

function MP:Open(opts)
    if not self.frame then self:Build() end
    self.opts = opts
    local f = self.frame
    W.SetTitle(f, opts.title or "Choose a Character")
    f:ClearAllPoints()
    local anchor = ns.DetailPanel.frame
    if anchor and anchor:IsShown() then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER")
    end
    self.search:SetText("")
    f:Show()
    self:Refresh()
    self.search:SetFocus()
end

function MP:Pick(full)
    local cb = self.opts and self.opts.onPick
    self.frame:Hide()
    if cb then cb(full) end
end

function MP:Hide()
    if self.frame then self.frame:Hide() end
end
