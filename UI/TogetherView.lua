--[[
    Nootropic Guild Manager - Play Together tab (everyone)
    Who to play with right now:

      Online now        guildmates online within a few levels of you
                        (Settings().playRange, 5 by default; 0 = any level),
                        people in your zone first
      Usually on now    guildmates who aren't online but usually play at
                        this hour (from their shared "usually online" hours)

    Your own characters (you and your alts) are left out. Click someone for
    their profile.
]]
local _, ns = ...
local W = ns.Widgets
local TV = {}
ns.TogetherView = TV

local ROW_H = 22
local HEADER_H = 26
local RANGES = { 3, 5, 10, 0 }
local GRAY = "|cff9d9d9d"

function TV:Range()
    local r = ns.DB:Settings().playRange
    if r == nil then return 5 end
    return r
end

local function RangeText(r)
    return r == 0 and "Any level" or ("Within " .. r .. " levels")
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
-- Your level and zone, and the main your characters share.
local function Me()
    local me = ns.Roster.byName[ns.PlayerFullName()]
    local level = (me and me.level and me.level > 0 and me.level) or (UnitLevel and UnitLevel("player")) or 1
    local zone = (me and me.zone ~= "" and me.zone) or (GetRealZoneText and GetRealZoneText()) or ""
    local group = me and (me.main or me.full) or ns.PlayerFullName()
    return level, zone, group
end

-- { online = { e... }, usual = { e... }, level, zone }
function TV:Lists()
    local level, zone, myGroup = Me()
    local range = self:Range()
    local online, usual = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        local group = e.main or e.full
        if group ~= myGroup and not e.isSelf then
            if e.online then
                if range == 0 or math.abs((e.level or 0) - level) <= range then online[#online + 1] = e end
            elseif ns.Profile:UsuallyOnNow(e.full) then
                usual[#usual + 1] = e
            end
        end
    end
    local function closer(a, b)
        local da, db = math.abs((a.level or 0) - level), math.abs((b.level or 0) - level)
        if da ~= db then return da < db end
        return a.short < b.short
    end
    table.sort(online, function(a, b)
        local za, zb = a.zone == zone, b.zone == zone
        if za ~= zb then return za end
        return closer(a, b)
    end)
    table.sort(usual, closer)
    return { online = online, usual = usual, level = level, zone = zone }
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
function TV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)

    local range = W.Button(page, "", 140, 22)
    range:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    range:SetScript("OnClick", function(btn)
        local items = { { text = "Online now", isTitle = true } }
        for _, r in ipairs(RANGES) do
            items[#items + 1] = { text = RangeText(r), radio = true,
                checked = function() return TV:Range() == r end,
                func = function() ns.DB:Settings().playRange = r; TV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(range, "Level range", "How close to your level guildmates online now must be.")
    self.rangeButton = range

    local inset = frame.Inset
    local scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, e) return e.header and HEADER_H or ROW_H end)
    view:SetElementInitializer("Button", function(row, e) TV:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    -- online status and "usually on" move with the clock: refresh each minute
    local elapsed = 0
    page:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 60 then
            elapsed = 0
            TV:Refresh()
        end
    end)
    page:SetScript("OnShow", function()
        ns.Roster:Request()
        TV:Refresh()
    end)
    ns:On("ROSTER_UPDATED", function() if page:IsVisible() then ns.Debounce("togetherview", 0.2, function() TV:Refresh() end) end end)
end

local function Text(row, font)
    local fs = row:CreateFontString(nil, "OVERLAY", font or "NGMFontText")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function TV:InitRow(row, e)
    if not row.built then
        row.built = true
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.Header = Text(row, "NGMFontLabel")
        row.Header:SetPoint("LEFT", 6, -2)
        row.Line = row:CreateTexture(nil, "ARTWORK")
        row.Line:SetHeight(1)
        ns.Theme:Paint(row.Line, ns.Theme.C.yellow, 0.25)
        row.Line:SetPoint("LEFT", row.Header, "RIGHT", 8, 0)
        row.Line:SetPoint("RIGHT", -6, 0)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(16, 16)
        row.Icon:SetPoint("LEFT", 6, 0)
        row.Name = Text(row)
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
        row.Name:SetWidth(170)
        row.Level = Text(row, "NGMFontTextSmall")
        row.Level:SetPoint("LEFT", row.Name, "RIGHT", 6, 0)
        row.Level:SetWidth(96)
        row.Where = Text(row, "NGMFontTextSmall")
        row.Where:SetPoint("LEFT", row.Level, "RIGHT", 6, 0)
        row.Where:SetWidth(220)
        row.Spec = Text(row, "NGMFontDimSmall")
        row.Spec:SetPoint("LEFT", row.Where, "RIGHT", 6, 0)
        row.Spec:SetPoint("RIGHT", -8, 0)
        row:SetScript("OnClick", function(self)
            if self.entry and self.entry.full then ns.DetailPanel:Show(self.entry.full, ns.UI.frame) end
        end)
        row:SetScript("OnEnter", function(self)
            local en = self.entry
            if en and en.full then ns.RosterView:ShowRowTooltip(self, en, "Click for their profile.") end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.entry = e
    local header = e.header ~= nil
    row.Header:SetShown(header)
    row.Line:SetShown(header)
    for _, fs in ipairs({ row.Icon, row.Name, row.Level, row.Where, row.Spec }) do fs:SetShown(not header) end
    row:EnableMouse(not header)
    if header then
        row:SetHeight(HEADER_H)
        row.Header:SetText(e.header)
        return
    end
    row:SetHeight(ROW_H)
    W.SetClassIcon(row.Icon, e.classFile)
    row.Name:SetText(e.short)
    row.Name:SetTextColor(ns.ClassColor(e.classFile))
    local diff = (e.level or 0) - (self.myLevel or 0)
    local diffText = diff == 0 and "" or (GRAY .. (diff > 0 and (" (+" .. diff .. ")") or (" (" .. diff .. ")")) .. "|r")
    row.Level:SetText(("Level %d%s"):format(e.level or 0, diffText))
    if e.online then
        local same = e.zone ~= "" and e.zone == self.myZone
        row.Where:SetText(same and ("|cff20ff20" .. e.zone .. "|r  " .. GRAY .. "(your zone)|r") or (e.zone ~= "" and e.zone or "-"))
    else
        row.Where:SetText(GRAY .. "Last online " .. ns.FormatLastSeen(e.lastOnline) .. " ago|r")
    end
    local bits = {}
    if e.spec then bits[#bits + 1] = e.spec end
    if e.roleList and #e.roleList > 0 then bits[#bits + 1] = table.concat(e.roleList, "/") end
    row.Spec:SetText(table.concat(bits, "  "))
end

function TV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local lists = self:Lists()
    self.myLevel, self.myZone = lists.level, lists.zone
    self.title:SetText(("Play Together  " .. GRAY .. "- you're level %d%s|r"):format(lists.level,
        lists.zone ~= "" and (" in " .. lists.zone) or ""))
    self.rangeButton:SetText(RangeText(self:Range()))

    local data = {}
    local range = self:Range()
    data[#data + 1] = { header = ("Online now %s(%d)|r"):format(GRAY, #lists.online) .. (range > 0 and (GRAY .. "  within " .. range .. " levels of you|r") or "") }
    if #lists.online == 0 then
        data[#data + 1] = { header = GRAY .. (IsInGuild() and "Nobody near your level is online right now." or "Join a guild to see who's around.") .. "|r" }
    end
    for _, e in ipairs(lists.online) do data[#data + 1] = e end
    data[#data + 1] = { header = ("Usually on around now %s(%d)|r"):format(GRAY, #lists.usual) .. GRAY .. "  offline, but they often play at this hour|r" }
    if #lists.usual == 0 then
        data[#data + 1] = { header = GRAY .. "Nobody else usually plays at this hour (only guildmates using the addon share their hours).|r" }
    end
    for _, e in ipairs(lists.usual) do data[#data + 1] = e end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(data), retain)
end
