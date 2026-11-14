--[[
    Nootropic Guild Manager - Do Not Whisper window
    Everyone recruiters shouldn't contact right now, shared with the guild:

      Do not whisper   on the list for good (they asked, or someone added
                       them by hand)
      Whispered        someone in the guild whispered them; nobody can
                       whisper them again until RC.RECONTACT_DAYS have passed

    Also adds "Add to Do Not Whisper" to the game's right-click menu on
    player names: in chat (whispers included), on your target, party and raid.

    ns.DNWView:Open()
]]
local _, ns = ...
local W = ns.Widgets
local DV = {}
ns.DNWView = DV

local ROW_H = 22
local RED, GRAY = "|cffff2020", "|cff9d9d9d"

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function DV:Build()
    local f = CreateFrame("Frame", "NootropicGMDNWWindow", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(460, 480)
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
    W.SetTitle(f, "Do Not Whisper")
    self.frame = f

    local search = CreateFrame("EditBox", "NootropicGMDNWSearch", f, "SearchBoxTemplate")
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", 16, -32)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText("Search names...") end
    search:HookScript("OnTextChanged", function() DV:Refresh() end)
    self.search = search

    -- what to show: everything, only the permanent list, only recent whispers
    self.show = "all"
    local show = W.Button(f, "", 150, 22)
    show:SetPoint("TOPRIGHT", -14, -31)
    show:SetScript("OnClick", function(btn)
        local function pick(key) return function() DV.show = key; DV:Refresh() end end
        W.ShowMenu(btn, {
            { text = "Show", isTitle = true },
            { text = "Everyone", radio = true, checked = function() return DV.show == "all" end, func = pick("all") },
            { text = "Do not whisper", radio = true, checked = function() return DV.show == "dnw" end, func = pick("dnw") },
            { text = "Recently whispered", radio = true, checked = function() return DV.show == "locked" end, func = pick("locked") },
        })
    end)
    self.showButton = show

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -60)
    scrollBox:SetPoint("BOTTOMRIGHT", -26, 34)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, e) DV:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.empty = f:CreateFontString(nil, "OVERLAY", "NGMFontDim")
    self.empty:SetPoint("CENTER", scrollBox, "CENTER")

    self.summary = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.summary:SetPoint("BOTTOMLEFT", 16, 12)
    self.summary:SetPoint("BOTTOMRIGHT", -16, 12)
    self.summary:SetJustifyH("LEFT")

    -- countdowns move slowly: refresh once a minute while open
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 60 then
            elapsed = 0
            DV:Refresh()
        end
    end)
    ns:On("RECRUITS_CHANGED", function() if f:IsShown() then ns.Debounce("dnwview", 0.2, function() DV:Refresh() end) end end)
end

local function When(t) return t and date("%b %d", t) or "?" end

function DV:InitRow(row, e)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.Name = row:CreateFontString(nil, "OVERLAY", "NGMFontText")
        row.Name:SetPoint("LEFT", 6, 0)
        row.Name:SetWidth(170)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.State = row:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        row.State:SetPoint("LEFT", row.Name, "RIGHT", 6, 0)
        row.State:SetWidth(130)
        row.State:SetJustifyH("LEFT")
        row.By = row:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
        row.By:SetPoint("RIGHT", -6, 0)
        row.By:SetPoint("LEFT", row.State, "RIGHT", 4, 0)
        row.By:SetJustifyH("RIGHT")
        row.By:SetWordWrap(false)
        row:SetScript("OnClick", function(self) DV:ShowRowMenu(self, self.entry) end)
        row:SetScript("OnEnter", function(self) DV:ShowRowTooltip(self, self.entry) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.entry = e
    row.Name:SetText(ns.ShortName(e.full))
    if e.kind == "dnw" then
        row.State:SetText(RED .. "Do not whisper|r")
        row.By:SetText(When(e.at) .. ", " .. ns.ShortName(e.by or "?"))
    else
        row.State:SetText(ns.GOLD .. ns.FormatWait(e.untilT - ns.DB:Now()) .. " left|r")
        row.By:SetText("whispered " .. When(e.whispered) .. (e.by and (", " .. ns.ShortName(e.by)) or ""))
    end
end

function DV:ShowRowTooltip(row, e)
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ShortName(e.full))
    if e.kind == "dnw" then
        GameTooltip:AddLine("On the Do Not Whisper list for good.", 1, 0.4, 0.4, true)
        GameTooltip:AddDoubleLine("Added", date("%b %d, %Y", e.at or 0), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1)
        GameTooltip:AddDoubleLine("By", ns.ShortName(e.by or "?"), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1)
        if e.reply and e.reply ~= "" then GameTooltip:AddLine("\"" .. e.reply .. "\"", 0.8, 0.8, 0.8, true) end
    else
        GameTooltip:AddLine(("Whispered recently: nobody in the guild can whisper them again for %s."):format(
            ns.FormatWait(e.untilT - ns.DB:Now())), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], true)
        GameTooltip:AddDoubleLine("Whispered", date("%b %d, %Y", e.whispered), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1)
        if e.by then GameTooltip:AddDoubleLine("Last update by", ns.ShortName(e.by), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1) end
        if e.replied then GameTooltip:AddDoubleLine("Replied", date("%b %d", e.replied), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1) end
        if e.invited then GameTooltip:AddDoubleLine("Invited", date("%b %d", e.invited), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3], 1, 1, 1) end
        if e.reply then GameTooltip:AddLine("\"" .. e.reply .. "\"", 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:AddLine("Click for options.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function DV:ShowRowMenu(row, e)
    if not e then return end
    local name = ns.ShortName(e.full)
    local items = { { text = name, isTitle = true } }
    if e.kind == "dnw" then
        items[#items + 1] = { text = "Take off the Do Not Whisper list", func = function()
            W.Confirm(("Take %s off the Do Not Whisper list for everyone?"):format(name),
                function() ns.Recruit:RemoveDNW(e.full) end)
        end }
    else
        items[#items + 1] = { text = "Add to Do Not Whisper (for good)", func = function()
            ns.Recruit:AddDNW(e.full, "(added by hand)")
        end }
    end
    W.ShowMenu(row, items)
end

-- Both lists in one, filtered by the search box and the Show menu.
function DV:Entries()
    local query = ns.Trim(self.search:GetText() or ""):lower()
    local out, nDNW, nLocked = {}, 0, 0
    local function keep(e)
        return query == "" or ns.ShortName(e.full):lower():find(query, 1, true)
    end
    for _, d in ipairs(ns.Recruit:DNWList()) do
        nDNW = nDNW + 1
        d.kind = "dnw"
        if self.show ~= "locked" and keep(d) then out[#out + 1] = d end
    end
    for _, l in ipairs(ns.Recruit:LockedList()) do
        nLocked = nLocked + 1
        l.kind = "locked"
        if self.show ~= "dnw" and keep(l) then out[#out + 1] = l end
    end
    return out, nDNW, nLocked
end

local SHOW_LABELS = { all = "Show: Everyone", dnw = "Show: Do not whisper", locked = "Show: Recently whispered" }

function DV:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local list, nDNW, nLocked = self:Entries()
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    self.showButton:SetText(SHOW_LABELS[self.show])
    if not IsInGuild() then
        self.empty:SetText("Join a guild to see the list.")
    else
        self.empty:SetText(#list == 0 and "Nobody here." or "")
    end
    self.summary:SetText(("%s%d|r do not whisper  -  %s%d|r whispered in the last %d days  %s(shared with the guild)|r"):format(
        RED, nDNW, ns.GOLD, nLocked, ns.Recruit.RECONTACT_DAYS, GRAY))
end

function DV:Open()
    if not self.frame then self:Build() end
    local f = self.frame
    if not f:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end
    f:Show()
    self:Refresh()
end

function DV:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

------------------------------------------------------------------------
-- Right-click menus on player names (Menu.ModifyMenu, the official way)
------------------------------------------------------------------------
-- FRIEND is the menu for names in chat (whispers included); the others are
-- unit frames. Enemy players can't join, so they're left out.
local MENUS = {
    "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_CHAT_ROSTER",
}

local function NameFrom(contextData)
    local cd = contextData or {}
    local name = cd.name
    if cd.unit and UnitIsPlayer and UnitIsPlayer(cd.unit) and GetUnitName then
        name = GetUnitName(cd.unit, true) or name
    end
    if not name or name == "" then return nil end
    return ns.NormalizeName(name)
end

function DV:AddMenu(root, contextData)
    if not (IsInGuild() and ns.DB:Guild()) then return end
    local full = NameFrom(contextData)
    if not full or full == ns.PlayerFullName() then return end
    if ns.Roster.byName[full] then return end -- a guildmate, not a recruit
    local RC = ns.Recruit
    root:CreateDivider()
    root:CreateTitle("Nootropic Guild Manager")
    if RC:IsDNW(full) then
        root:CreateButton("Take off Do Not Whisper", function() RC:RemoveDNW(full) end)
    else
        root:CreateButton("Add to Do Not Whisper", function()
            RC:AddDNW(full, "(added by hand)")
            ns:Print(("%s is on the Do Not Whisper list. Nobody in the guild will whisper or invite them."):format(ns.ShortName(full)))
        end)
    end
end

function DV:Init()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData)
            ns.Safe(function() DV:AddMenu(root, contextData) end, "DNWView")()
        end)
    end
end
