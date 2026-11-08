--[[
    Nootropic Guild Manager - Character profile flyout
    Opens beside the roster. Two modes:

      Read (default)  header (name, level, spec, class, rank, location),
                      main/alt line, contact, tags they have, usual online
                      hours (learned from play time), then tabs:
                        Profile   professions
                        Notes     your private notes about them
                        Officer   officer log, change history (officers)
      Edit            contact, spec, roles, tags, professions and main/alt
                      links, each as far as your rank may

    The Edit button shows when you may edit something: always your own
    characters, others when the Guild Master's permissions allow.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local DP = {}
ns.DetailPanel = DP

local WIDTH = 352
local INNER = WIDTH - 52 -- scroll child width (room for the scroll bar)
local MAX_PROFS = 6
local SECTION_GAP = 14

DP.tab = "profile"
DP.schedOpen = false     -- the week grid starts folded (summary line only)

-- A small gold text link ("Show week").
local function TextLink(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(16)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Text:SetPoint("LEFT", 0, 0)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self.Text:SetTextColor(1, 0.82, 0) end)
    function b:SetLabel(text)
        self.Text:SetText(text)
        self:SetWidth(math.ceil(self.Text:GetStringWidth()) + 4)
    end
    return b
end

------------------------------------------------------------------------
-- Small builders
------------------------------------------------------------------------
local function NewSection(parent, title)
    local s = CreateFrame("Frame", nil, parent)
    s:SetWidth(INNER)
    if title then
        s.Title, s.Line = W.SectionHeader(s, title)
        s.Title:SetPoint("TOPLEFT", 0, 0)
    end
    return s
end

local function Para(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWidth(width or INNER)
    fs:SetSpacing(2)
    return fs
end

local function SmallButton(parent, text, width)
    local b = W.Button(parent, text, width or 70, 18)
    return b
end

-- Clickable character name (opens that profile).
local function NameLink(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetSize(14, 14)
    b.Icon:SetPoint("LEFT", 0, 0)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Text:SetPoint("LEFT", b.Icon, "RIGHT", 4, 0)
    b.Underline = b:CreateTexture(nil, "OVERLAY")
    b.Underline:SetHeight(1)
    b.Underline:SetPoint("TOPLEFT", b.Text, "BOTTOMLEFT", 0, -1)
    b.Underline:SetPoint("TOPRIGHT", b.Text, "BOTTOMRIGHT", 0, -1)
    b.Underline:SetColorTexture(1, 1, 1, 0.5)
    b.Underline:Hide()
    b:SetScript("OnEnter", function(self)
        self.Underline:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.inRoster and "Open this profile" or "Not in the guild roster right now", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.Underline:Hide(); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.inRoster then ns.RosterView:Select(self.full) end
    end)
    function b:SetCharacter(full)
        self.full = full
        local e = ns.Roster.byName[full]
        self.inRoster = e ~= nil
        self.Text:SetText(ns.ShortName(full) .. (e and "" or " |cff6d6d6d(not in guild)|r"))
        if e then
            W.SetClassIcon(self.Icon, e.classFile)
            self.Text:SetTextColor(ns.ClassColor(e.classFile))
        else
            W.SetIcon(self.Icon, D.UNKNOWN_ICON)
            self.Text:SetTextColor(0.7, 0.7, 0.7)
        end
        self:SetWidth(math.ceil(self.Text:GetStringWidth()) + 20)
    end
    return b
end

local function SmallX(parent, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    b:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    b:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    if tip then W.Tooltip(b, tip) end
    return b
end

-- Places frames left to right, wrapping at INNER. Returns the height used.
local function Flow(items, startY, gapX, gapY, rowH)
    local x, y = 0, startY
    for _, it in ipairs(items) do
        local w = it:GetWidth()
        if x > 0 and x + w > INNER then
            x = 0
            y = y - rowH - gapY
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", x, y)
        it:Show()
        x = x + w + gapX
    end
    return -(y - rowH)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function DP:Build(parent)
    local f = CreateFrame("Frame", "NootropicGMDetailFrame", parent, "BasicFrameTemplateWithInset")
    f:SetWidth(WIDTH)
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -28)
    f:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 0, 4)
    f:EnableMouse(true)
    f:Hide()
    W.SetTitle(f, "Character Profile")
    f:SetScript("OnHide", ns.Safe(function()
        DP:FlushNote()
        DP:FlushText()
        ns.MemberPicker:Hide()
        ns.RosterView:ClearSelection()
        DP.editing = false
    end, "closing the profile"))
    self.frame = f

    -- Edit / Done beside the close button
    local edit = W.Button(f, "Edit", 56, 18)
    local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
    if close then edit:SetPoint("RIGHT", close, "LEFT", -2, 0) else edit:SetPoint("TOPRIGHT", -30, -3) end
    edit:SetFrameLevel((close and close:GetFrameLevel() or f:GetFrameLevel() + 10) + 1)
    edit:SetScript("OnClick", function() DP:SetEditing(not DP.editing) end)
    edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(DP.editing and "Done" or "Edit")
        GameTooltip:AddLine(DP.editing and "Back to the profile." or "Change this profile.", 1, 1, 1)
        GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.editBtn = edit

    local scroll = W.TryCreate("ScrollFrame", "NootropicGMDetailScroll", f, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 28)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(INNER, 400)
    scroll:SetScrollChild(content)
    self.content = content

    self:BuildHeader(content)
    -- read mode
    self.linkLine = self:BuildLinkLine(content)
    self.contactBox = self:BuildContactBox(content)
    self.tagsRead = self:BuildTagSection(content, "read")
    self.schedule = self:BuildScheduleSection(content)
    self.tabs = self:BuildTabs(content)
    -- tab contents (and edit mode)
    self:BuildProfSection(content)
    self:BuildNoteSection(content)
    self:BuildLogSection(content)
    self:BuildHistorySection(content)
    -- edit mode
    self.editContact = self:BuildEditContact(content)
    self:BuildAltSection(content)
    self:BuildSpecSection(content)
    self:BuildRoleSection(content)
    self.tagsEdit = self:BuildTagSection(content, "edit")

    self.allSections = {
        self.linkLine, self.contactBox, self.tagsRead, self.schedule, self.tabs,
        self.prof, self.note, self.log, self.history,
        self.editContact,
        self.alt, self.spec, self.role, self.tagsEdit,
    }

    self.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.footer:SetPoint("BOTTOMLEFT", 14, 10)
    self.footer:SetPoint("BOTTOMRIGHT", -14, 10)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetWordWrap(false)

    local function refresh()
        if f:IsShown() then ns.Debounce("detail", 0.05, function() DP:Refresh() end) end
    end
    ns:On("ROSTER_UPDATED", refresh)
    ns:On("GUILD_SETTINGS_CHANGED", refresh) -- permissions changed
    ns:On("AUDIT_CHANGED", function()
        if f:IsShown() and DP.tab == "officer" then ns.Debounce("detailhistory", 0.2, function() DP:Refresh() end) end
    end)
end

------------------------------------------------------------------------
-- Header: icon, name, "Level 22 Feral Druid - Veteran", where they are
------------------------------------------------------------------------
function DP:BuildHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(INNER, 48)
    h:SetPoint("TOPLEFT")

    local iconBorder = CreateFrame("Frame", nil, h, "BackdropTemplate")
    iconBorder:SetSize(42, 42)
    iconBorder:SetPoint("TOPLEFT", 0, 0)
    iconBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    iconBorder:SetBackdropBorderColor(0.6, 0.6, 0.6)
    h.Icon = iconBorder:CreateTexture(nil, "ARTWORK")
    h.Icon:SetPoint("TOPLEFT", 4, -4)
    h.Icon:SetPoint("BOTTOMRIGHT", -4, 4)

    h.Name = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.Name:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 8, -1)
    h.Name:SetPoint("RIGHT", 0, 0)
    h.Name:SetJustifyH("LEFT")
    h.Name:SetWordWrap(false)

    h.Sub = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.Sub:SetPoint("TOPLEFT", h.Name, "BOTTOMLEFT", 0, -3)
    h.Sub:SetPoint("RIGHT", 0, 0)
    h.Sub:SetJustifyH("LEFT")
    h.Sub:SetWordWrap(false)

    h.Status = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.Status:SetPoint("TOPLEFT", h.Sub, "BOTTOMLEFT", 0, -2)
    h.Status:SetJustifyH("LEFT")
    h.Status:SetWordWrap(false)

    self.header = h
end

function DP:RefreshHeader(e)
    local h = self.header
    W.SetClassIcon(h.Icon, e.classFile)
    h.Name:SetText(e.short)
    h.Name:SetTextColor(ns.ClassColor(e.classFile))
    local specIcon = e.spec and D:SpecIcon(e.classFile, e.spec)
    local spec = e.spec and ((specIcon and ("|T" .. specIcon .. ":12:12:0:0:64:64:5:59:5:59|t ") or "") .. e.spec .. " ") or ""
    local roles = (e.roleList and #e.roleList > 0) and ("  |cff9d9d9d-|r  " .. table.concat(e.roleList, ", ")) or ""
    h.Sub:SetText(("Level %d %s%s  |cff9d9d9d-|r  %s%s"):format(e.level, spec, e.className, e.rank, roles))
    if e.online then
        h.Status:SetText("|cff40ff40Online|r  " .. (e.zone ~= "" and e.zone or ""))
    else
        h.Status:SetText("|cff9d9d9dOffline - last seen " .. ns.FormatLastSeen(e.lastOnline) .. " ago|r")
    end
end

------------------------------------------------------------------------
-- Read mode: main / alt line
------------------------------------------------------------------------
function DP:BuildLinkLine(parent)
    local s = NewSection(parent)
    s.Label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.Label:SetPoint("TOPLEFT", 0, -2)
    s.links = {}
    return s
end

function DP:RefreshLinkLine(e)
    local s = self.linkLine
    for _, l in ipairs(s.links) do l:Hide() end
    local names = e.isAlt and { e.main } or e.alts
    if e.isAlt then
        s.Label:SetText("|cff9d9d9dAlt of|r")
    elseif #names == 0 then
        s.Label:SetText("|cff9d9d9dMain character  -  no alts linked|r")
    else
        s.Label:SetText(("|cff9d9d9dMain  -  %s:|r"):format(#names == 1 and "1 alt" or (#names .. " alts")))
    end
    local x, y = math.ceil(s.Label:GetStringWidth()) + 6, 0
    for i, full in ipairs(names) do
        local l = s.links[i]
        if not l then
            l = NameLink(s)
            s.links[i] = l
        end
        l:SetCharacter(full)
        if x + l:GetWidth() > INNER then
            x, y = 0, y - 18
        end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", x, y + 1)
        l:Show()
        x = x + l:GetWidth() + 6
    end
    s:SetHeight(-y + 18)
end

------------------------------------------------------------------------
-- Read mode: contact
------------------------------------------------------------------------
-- A box with the text selected, to copy with Ctrl+C.
StaticPopupDialogs.NOOTROPICGM_COPY = {
    text = "Press Ctrl+C to copy, then Escape.",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 240,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if box and data then
            box:SetText(data.text or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
}

-- Contact: Discord name (click to copy) and the contact note.
function DP:BuildContactBox(parent)
    local s = NewSection(parent)
    s.Label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.Label:SetPoint("TOPLEFT", 0, -2)
    s.Label:SetText("Discord:")
    s.Discord = TextLink(s, function()
        local e = DP.entry
        local discord = e and ns.Profile:Contact(e.full)
        if discord and discord ~= "" then StaticPopup_Show("NOOTROPICGM_COPY", nil, nil, { text = discord }) end
    end)
    s.Discord:SetPoint("LEFT", s.Label, "RIGHT", 6, 0)
    W.Tooltip(s.Discord, "Discord", "Click to copy.")
    s.Note = Para(s, "GameFontHighlightSmall", INNER)
    s.From = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    return s
end

function DP:RefreshContactBox(e)
    local s = self.contactBox
    local discord, note, fromMain = ns.Profile:Contact(e.full)
    if not discord then return false end
    local y = 0
    local hasDiscord = discord ~= ""
    s.Label:SetShown(hasDiscord)
    s.Discord:SetShown(hasDiscord)
    if hasDiscord then
        s.Discord:SetLabel(discord)
        y = -16
    end
    s.Note:ClearAllPoints()
    s.Note:SetPoint("TOPLEFT", 0, y - 2)
    s.Note:SetText(note ~= "" and ("|cffffd100Contact:|r " .. note) or "")
    if note ~= "" then y = y - 2 - math.ceil(s.Note:GetStringHeight()) end
    s.From:ClearAllPoints()
    s.From:SetPoint("TOPLEFT", 0, y - 3)
    s.From:SetText(fromMain and ("From their main, " .. ns.ShortName(fromMain)) or "")
    if fromMain then y = y - 15 end
    s:SetHeight(-y + 2)
    return true
end

------------------------------------------------------------------------
-- Tags: read mode shows theirs, edit mode shows all to toggle
------------------------------------------------------------------------
function DP:BuildTagSection(parent, mode)
    local s = NewSection(parent, mode == "edit" and "Tags" or nil)
    s.mode = mode
    s.pills = {}
    if mode == "edit" then
        s.Hint = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s.Hint:SetPoint("LEFT", s.Title, "RIGHT", 6, 0)
        s.Hint:SetText("click to turn on or off")
        s.Line:SetPoint("LEFT", s.Hint, "RIGHT", 6, 0)
    end
    return s
end

function DP:LayoutTags(s, e)
    local m = ns.DB:GetMember(e.full)
    local set = (m and m.tags) or {}
    local items = {}
    for _, tag in ipairs(ns.DB:GetTags()) do
        if s.mode == "edit" or set[tag.id] then
            local i = #items + 1
            local p = s.pills[i]
            if not p then
                p = W.Pill(s, 18, 16)
                p:SetScript("OnClick", function(self)
                    if s.mode == "edit" and DP.entry and self.tag and ns.DB:CanEditTags(DP.entry.full) then
                        ns.DB:SetTag(DP.entry.full, self.tag.id)
                        ns.PlaySound("U_CHAT_SCROLL_BUTTON")
                    end
                end)
                p:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.tag and D:TagLabel(self.tag) or "")
                    if s.mode == "edit" then
                        GameTooltip:AddLine("Click to turn on or off. Shared with the guild.", 1, 1, 1, true)
                    end
                    GameTooltip:Show()
                end)
                p:SetScript("OnLeave", function() GameTooltip:Hide() end)
                s.pills[i] = p
            end
            p:SetTag(tag, s.mode == "read" or (set[tag.id] and true or false))
            items[#items + 1] = p
        end
    end
    for i = #items + 1, #s.pills do s.pills[i]:Hide() end
    if #items == 0 then return false end
    local top = s.mode == "edit" and -22 or 0
    s:SetHeight(Flow(items, top, 4, 4, 18))
    return true
end

------------------------------------------------------------------------
-- Usually online (read mode). Times follow your game clock: local time when
-- its "Use Local Time" box is ticked, otherwise server time.
------------------------------------------------------------------------
function DP:BuildScheduleSection(parent)
    local s = NewSection(parent, "Usually Online")
    s.Summary = Para(s, "GameFontHighlightSmall", INNER)
    s.Summary:SetPoint("TOPLEFT", 0, -22)
    -- the week grid folds away; the summary line is enough most of the time
    s.Toggle = TextLink(s, function()
        DP.schedOpen = not DP.schedOpen
        DP:Refresh()
    end)
    s.Grid = ns.ScheduleGrid.New(s, {
        cell = 19, cellH = 11,
        onHover = function(cell, day, block) DP:ScheduleTooltip(cell, day, block) end,
    })
    return s
end

-- "Fri 8 pm-10 pm (local time) - 11 pm-1 am server time"
function DP:ScheduleTooltip(cell, day, block)
    local e = self.entry
    if not e then return end
    local PF = ns.Profile
    local mode = PF.ClockMode()
    local h = block * 2
    local on = self.schedule.Grid:Block(day, block)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s %s-%s  |cff9d9d9d(%s)|r"):format(PF.DAYS[day + 1], PF.HourText(h), PF.HourText(h + 2), PF.ClockLabel(mode)))
    -- the same hours on the other clock
    local off = PF.LocalMinusServer()
    if off and off ~= 0 then
        local idx = (day * 24 + h + (mode == "local" and -off or off)) % 168
        local od, oh = math.floor(idx / 24), idx % 24
        GameTooltip:AddLine(("= %s %s-%s %s"):format(PF.DAYS[od + 1], PF.HourText(oh), PF.HourText(oh + 2),
            mode == "local" and "server time" or "your local time"), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(on and "Usually online" or "Usually not online", on and 0.4 or 0.6, on and 1 or 0.6, on and 0.4 or 0.6)
    GameTooltip:AddLine("Times follow your game clock's Use Local Time setting.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

function DP:RefreshSchedule(e)
    local s = self.schedule
    local PF = ns.Profile
    local mode = PF.ClockMode()
    local bits = PF:Hours(e.full, mode)
    if not bits or not next(bits) then return false end
    local open = self.schedOpen
    s.Summary:SetText((PF.Summary(bits) or "") .. ("  |cff9d9d9d(%s)|r"):format(PF.ClockLabel(mode)))
    local sh = math.ceil(s.Summary:GetStringHeight())
    s.Toggle:SetLabel(open and "Hide week" or "Show week")
    s.Toggle:ClearAllPoints()
    s.Toggle:SetPoint("TOPLEFT", 0, -22 - sh - 4)
    local h = 22 + sh + 4 + 16
    s.Grid.frame:SetShown(open)
    if open then
        s.Grid:SetBits(bits)
        s.Grid.frame:ClearAllPoints()
        s.Grid.frame:SetPoint("TOPLEFT", 0, -h - 4)
        h = h + 4 + s.Grid.frame:GetHeight()
    end
    s:SetHeight(h)
    return true
end

------------------------------------------------------------------------
-- Tabs: Profile / Notes / Officer
------------------------------------------------------------------------
function DP:BuildTabs(parent)
    local s = NewSection(parent)
    s:SetHeight(22)
    s.Line = s:CreateTexture(nil, "ARTWORK")
    s.Line:SetHeight(1)
    s.Line:SetPoint("BOTTOMLEFT")
    s.Line:SetPoint("BOTTOMRIGHT")
    s.Line:SetColorTexture(0.6, 0.5, 0.3, 0.6)
    s.buttons = {}
    local x = 0
    for _, t in ipairs({ { "profile", "Profile" }, { "notes", "Notes" }, { "officer", "Officer" } }) do
        local b = CreateFrame("Button", nil, s, "BackdropTemplate")
        b:SetHeight(20)
        b:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.Text:SetPoint("CENTER", 0, 0)
        b.Text:SetText(t[2])
        b:SetWidth(math.ceil(b.Text:GetStringWidth()) + 22)
        b:SetPoint("BOTTOMLEFT", x, 0)
        b.key = t[1]
        b:SetScript("OnClick", function() DP.tab = t[1]; ns.PlaySound("IG_CHARACTER_INFO_TAB"); DP:Refresh() end)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        x = x + b:GetWidth() + 3
        s.buttons[t[1]] = b
    end
    return s
end

function DP:RefreshTabs()
    local officer = ns.IsOfficer()
    if self.tab == "officer" and not officer then self.tab = "profile" end
    for key, b in pairs(self.tabs.buttons) do
        b:SetShown(key ~= "officer" or officer)
        if key == self.tab then
            b:SetBackdropColor(0.18, 0.14, 0.08, 1)
            b:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
            b.Text:SetTextColor(1, 0.82, 0)
        else
            b:SetBackdropColor(0.05, 0.04, 0.03, 1)
            b:SetBackdropBorderColor(0.35, 0.3, 0.22, 1)
            b.Text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

------------------------------------------------------------------------
-- Professions (read: bars; edit: add, remove, set levels)
------------------------------------------------------------------------
local function BuildProfRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(INNER, 22)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r:GetHighlightTexture():SetAlpha(0.3)

    r.Icon = r:CreateTexture(nil, "ARTWORK")
    r.Icon:SetSize(18, 18)
    r.Icon:SetPoint("LEFT", 0, 0)

    r.Name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.Name:SetPoint("LEFT", r.Icon, "RIGHT", 6, 0)
    r.Name:SetWidth(104)
    r.Name:SetJustifyH("LEFT")
    r.Name:SetWordWrap(false)

    local barFrame = CreateFrame("Frame", nil, r, "BackdropTemplate")
    barFrame:SetSize(126, 14)
    barFrame:SetPoint("RIGHT", -20, 0)
    barFrame:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    barFrame:SetBackdropColor(0, 0, 0, 0.6)
    barFrame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

    local bar = CreateFrame("StatusBar", nil, barFrame)
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.1, 0.35, 0.85)
    bar:SetMinMaxValues(0, 1)
    r.Bar = bar

    r.BarText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.BarText:SetPoint("CENTER", 0, 0)

    r.Remove = SmallX(r, "Remove profession")
    r.Remove:SetPoint("RIGHT", 0, 0)
    r.Remove:SetScript("OnClick", function()
        if DP.entry and r.prof then ns.DB:RemoveManualProf(DP.entry.full, r.prof.name) end
    end)

    r:SetScript("OnClick", function() if DP.editing then DP:EditProfRank(r.prof) end end)
    r:SetScript("OnEnter", function(self)
        local p = self.prof
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(p.name)
        if p.source == "addon" then
            GameTooltip:AddLine("Reported by their Nootropic Guild Manager addon, so it stays up to date.", 0.4, 1, 0.4, true)
        else
            GameTooltip:AddLine(DP.editing and "Added by hand. Click to set the skill level." or "Added by hand.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

function DP:BuildProfSection(parent)
    local s = NewSection(parent, "Professions")
    s.Add = SmallButton(s, "+ Add", 60)
    s.Add:SetPoint("TOPRIGHT", 0, 2)
    s.Add:SetScript("OnClick", function(btn) DP:ShowAddProfMenu(btn) end)

    s.rows = {}
    for i = 1, MAX_PROFS do
        local r = BuildProfRow(s)
        r:Hide()
        s.rows[i] = r
    end
    s.Divider = s:CreateTexture(nil, "ARTWORK")
    s.Divider:SetHeight(1)
    s.Divider:SetColorTexture(0.4, 0.35, 0.25, 0.5)

    s.Empty = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Empty:SetPoint("TOPLEFT", 0, -22)
    s.Empty:SetWidth(INNER)
    s.Empty:SetJustifyH("LEFT")
    self.prof = s
end

function DP:ShowAddProfMenu(owner)
    local e = self.entry
    if not e then return end
    local have = {}
    for _, p in ipairs(e.profs) do have[p.name:lower()] = true end
    local items = { { text = "Add profession", isTitle = true } }
    for _, p in ipairs(D.PROFESSIONS) do
        if not have[p.name:lower()] then
            items[#items + 1] = {
                text = "|T" .. p.icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. p.name,
                func = function() ns.DB:AddManualProf(e.full, p.name) end,
            }
        end
    end
    if #items == 1 then items[2] = { text = "All professions added", disabled = true } end
    W.ShowMenu(owner, items)
end

function DP:EditProfRank(p)
    local e = self.entry
    if not (e and p and p.source == "manual" and ns.DB:CanEditProfile(e.full)) then return end
    W.Prompt(("%s skill level for %s:"):format(p.name, e.short), p.rank > 0 and tostring(p.rank) or "", function(text)
        ns.DB:SetManualProfRank(e.full, p.name, tonumber(text) or 0)
    end, 3)
end

function DP:RefreshProfs(e)
    local s = self.prof
    local edit = self.editing and ns.DB:CanEditProfile(e.full)
    s.Add:SetShown(edit)
    s.Line:ClearAllPoints()
    s.Line:SetPoint("LEFT", s.Title, "RIGHT", 6, 0)
    s.Line:SetPoint("RIGHT", edit and s.Add or s, edit and "LEFT" or "RIGHT", edit and -6 or 0, 0)
    -- primary first, then secondary under a thin divider
    local y, shown, dividerAt = -22, 0, nil
    for i = 1, MAX_PROFS do
        local r, p = s.rows[i], e.profs[i]
        r.prof = p
        if p then
            if not dividerAt and not D:IsPrimary(p.name) and shown > 0 then
                dividerAt = y
                y = y - 6
            end
            W.SetIcon(r.Icon, D:ProfIcon(p))
            r.Name:SetText(p.name)
            local max = (p.max and p.max > 0) and p.max or D.PROF_MAX_RANK
            r.Bar:SetMinMaxValues(0, max)
            r.Bar:SetValue(p.rank or 0)
            if p.rank and p.rank > 0 then
                r.BarText:SetText(p.max and p.max > 0 and (p.rank .. " / " .. p.max) or tostring(p.rank))
            else
                r.BarText:SetText(edit and "|cff9d9d9dset level|r" or "|cff9d9d9d-|r")
            end
            r.Remove:SetShown(edit and p.source == "manual")
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, y)
            r:Show()
            y = y - 23
            shown = shown + 1
        else
            r:Hide()
        end
    end
    s.Divider:SetShown(dividerAt ~= nil)
    if dividerAt then
        s.Divider:ClearAllPoints()
        s.Divider:SetPoint("TOPLEFT", 24, dividerAt - 2)
        s.Divider:SetPoint("RIGHT", -20, 0)
    end
    s.Empty:SetShown(shown == 0)
    if shown == 0 then
        s.Empty:SetText(edit and "No professions yet. Use + Add." or "No professions known yet.")
        y = y - 18
    end
    s:SetHeight(-y + 2)
end

------------------------------------------------------------------------
-- Notes tab: private notes (only you; grows with its text)
------------------------------------------------------------------------
local NOTE_MIN_H = 60

function DP:BuildNoteSection(parent)
    local s = NewSection(parent, "Private Notes")
    s.Hint = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Hint:SetPoint("LEFT", s.Title, "RIGHT", 6, 0)
    s.Hint:SetText("only you")
    s.Line:SetPoint("LEFT", s.Hint, "RIGHT", 6, 0)

    local bg = CreateFrame("Button", nil, s, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 0, -22)
    bg:SetSize(INNER, NOTE_MIN_H)
    bg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.5)
    bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    s.Bg = bg

    local box = CreateFrame("EditBox", nil, bg)
    box:SetPoint("TOPLEFT", 8, -7)
    box:SetWidth(INNER - 16)
    box:SetMultiLine(true)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetAutoFocus(false)
    box:SetMaxLetters(500)
    box:SetTextInsets(0, 0, 0, 0)
    bg:SetScript("OnClick", function() box:SetFocus() end)

    s.Placeholder = bg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Placeholder:SetPoint("TOPLEFT", 8, -7)
    s.Placeholder:SetText("Click to write notes about this character.")

    box:HookScript("OnTextChanged", function(self, userInput)
        s.Placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        DP:SizeNote()
        if not userInput or not DP.entry then return end
        DP.pendingNote = { full = DP.entry.full, text = self:GetText() }
        ns.Debounce("note", 0.6, function() DP:FlushNote() end)
    end)
    box:HookScript("OnEditFocusGained", function() s.Placeholder:Hide() end)
    box:HookScript("OnEditFocusLost", function(self)
        s.Placeholder:SetShown(self:GetText() == "")
        DP:FlushNote()
    end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:HookScript("OnSizeChanged", function() DP:SizeNote() end)
    s.Box = box
    s:SetHeight(22 + NOTE_MIN_H)
    self.note = s
end

function DP:SizeNote()
    local s = self.note
    if not s then return end
    local h = math.max(NOTE_MIN_H, (s.Box:GetHeight() or 0) + 14)
    local changed = s.Bg:GetHeight() ~= h
    s.Bg:SetHeight(h)
    s:SetHeight(22 + h)
    if changed and self.entry and self.tab == "notes" then self:Layout() end
end

function DP:FlushNote()
    local p = self.pendingNote
    if p then
        self.pendingNote = nil
        ns.DB:SetNote(p.full, p.text)
    end
end

------------------------------------------------------------------------
-- Officer tab: officer log, change history
------------------------------------------------------------------------
function DP:BuildLogSection(parent)
    local s = NewSection(parent, "Officer Log")

    local input = CreateFrame("EditBox", "NootropicGMLogInput", s, "InputBoxTemplate")
    input:SetSize(INNER - 64, 20)
    input:SetPoint("TOPLEFT", 6, -22)
    input:SetAutoFocus(false)
    input:SetMaxLetters(D.MAX_LOG_LENGTH)
    input:SetFontObject("GameFontHighlightSmall")
    s.Input = input

    s.Add = SmallButton(s, "Add", 54)
    s.Add:SetPoint("TOPRIGHT", 0, -23)

    local function Submit()
        local e = DP.entry
        if not e then return end
        local entry = ns.DB:AddLogEntry(e.full, input:GetText())
        if entry then input:SetText("") end
        input:ClearFocus()
    end
    s.Add:SetScript("OnClick", Submit)
    input:SetScript("OnEnterPressed", Submit)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    W.Tooltip(input, "Add a log entry",
        "Short dated notes, e.g. \"Promoted to Raider\" or \"Missed raid without notice\".",
        "Shared with every officer running Nootropic Guild Manager. Members below officer rank never receive them.")

    s.Empty = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Empty:SetText("No entries yet.")
    s.entries = {}
    self.log = s
end

local function LogEntryFrame(s, i)
    local f = s.entries[i]
    if f then return f end
    f = CreateFrame("Frame", nil, s)
    f:SetWidth(INNER)
    f.Bar = f:CreateTexture(nil, "ARTWORK")
    f.Bar:SetWidth(2)
    f.Bar:SetPoint("TOPLEFT", 0, 0)
    f.Bar:SetPoint("BOTTOMLEFT", 0, 0)
    f.Bar:SetColorTexture(1, 0.82, 0, 0.5)
    f.Meta = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Meta:SetPoint("TOPLEFT", 8, 0)
    f.Meta:SetPoint("RIGHT", -20, 0)
    f.Meta:SetJustifyH("LEFT")
    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Text:SetPoint("TOPLEFT", f.Meta, "BOTTOMLEFT", 0, -3)
    f.Text:SetWidth(INNER - 12)
    f.Text:SetJustifyH("LEFT")
    f.Text:SetSpacing(2)
    f.Delete = SmallX(f, "Delete entry (for all officers)")
    f.Delete:SetPoint("TOPRIGHT", 0, 1)
    f.Delete:SetScript("OnClick", function()
        local e, entry = DP.entry, f.entry
        if not (e and entry) then return end
        W.Confirm("Delete this officer log entry for every officer?", function()
            ns.DB:DeleteLogEntry(e.full, entry.id)
        end)
    end)
    s.entries[i] = f
    return f
end

function DP:RefreshLog(e)
    local s = self.log
    local list = ns.DB:GetLog(e.full)
    local y = -50
    for i, entry in ipairs(list) do
        local f = LogEntryFrame(s, i)
        f.entry = entry
        f.Meta:SetText(ns.FormatDate(entry.ts) .. "  |cff9d9d9d-  " .. (entry.author or "?") .. "|r")
        f.Text:SetText(entry.text)
        local h = 12 + 3 + math.max(12, math.ceil(f.Text:GetStringHeight()))
        f:SetHeight(h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, y)
        f:Show()
        y = y - h - 8
    end
    for i = #list + 1, #s.entries do s.entries[i]:Hide() end
    s.Empty:ClearAllPoints()
    s.Empty:SetPoint("TOPLEFT", 6, y)
    s.Empty:SetShown(#list == 0)
    if #list == 0 then y = y - 16 end
    s:SetHeight(-y + 4)
end

local HISTORY_MAX = 15

function DP:BuildHistorySection(parent)
    local s = NewSection(parent, "Change History")
    s.rows = {}
    s.Empty = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Empty:SetText("No recorded changes yet.")
    s.All = SmallButton(s, "View all in Audit", 140)
    s.All:SetScript("OnClick", function()
        if not DP.entry then return end
        local full = DP.entry.full
        ns.UI:SelectTab(ns.UI.TAB_AUDIT)
        ns.AuditView:SetMember(full)
    end)
    self.history = s
end

local function HistoryRow(s, i)
    local r = s.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, s)
    r:SetWidth(INNER)
    r.Meta = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.Meta:SetPoint("TOPLEFT", 0, 0)
    r.Meta:SetPoint("RIGHT", 0, 0)
    r.Meta:SetJustifyH("LEFT")
    r.Text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.Text:SetPoint("TOPLEFT", r.Meta, "BOTTOMLEFT", 0, -2)
    r.Text:SetWidth(INNER - 4)
    r.Text:SetJustifyH("LEFT")
    s.rows[i] = r
    return r
end

function DP:RefreshHistory(e)
    local s = self.history
    local entries = ns.Audit:Entries({ member = e.full })
    local groups = ns.Audit:Group(entries)
    local y = -22
    local shown = math.min(#groups, HISTORY_MAX)
    for i = 1, shown do
        local g = groups[i]
        local r = HistoryRow(s, i)
        local lines = {}
        for _, entry in ipairs(g.entries) do lines[#lines + 1] = ns.Audit:Describe(entry) end
        r.Meta:SetText(ns.FormatDate(g.t) .. "  -  " .. ns.ShortName(g.author or "?")
            .. (#lines > 1 and ("  -  " .. #lines .. " changes") or ""))
        r.Text:SetText(table.concat(lines, "\n"))
        local h = 12 + 2 + math.max(12, math.ceil(r.Text:GetStringHeight()))
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:Show()
        y = y - h - 6
    end
    for i = shown + 1, #s.rows do s.rows[i]:Hide() end
    s.Empty:ClearAllPoints()
    s.Empty:SetPoint("TOPLEFT", 0, y)
    s.Empty:SetShown(shown == 0)
    if shown == 0 then y = y - 16 end
    s.All:ClearAllPoints()
    s.All:SetPoint("TOPLEFT", 0, y - 2)
    local audit = ns.TabName("audit")
    s.All:SetText(#groups > HISTORY_MAX and ("View all %d in %s"):format(#entries, audit) or ("View in %s tab"):format(audit))
    s:SetHeight(-y + 28)
end

------------------------------------------------------------------------
-- Edit mode: contact
------------------------------------------------------------------------
-- A text box with a counter; saved a moment after you stop typing.
local function EditText(s, maxLetters, height, multi, onSave)
    local bg = CreateFrame("Button", nil, s, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 0, -22)
    bg:SetSize(INNER, height)
    bg:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.5)
    bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    local box = CreateFrame("EditBox", nil, bg)
    box:SetPoint("TOPLEFT", 8, -6)
    box:SetPoint("RIGHT", -8, 0)
    box:SetMultiLine(multi)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    if not multi then box:SetHeight(height - 10) end
    bg:SetScript("OnClick", function() box:SetFocus() end)
    s.Count = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Count:SetPoint("TOPRIGHT", 0, -2)
    box:HookScript("OnTextChanged", function(self, user)
        s.Count:SetText(("%d / %d"):format(#self:GetText(), maxLetters))
        if user then
            DP.pendingText = DP.pendingText or {}
            DP.pendingText[onSave] = self:GetText()
            ns.Debounce("profiletext", 1, function() DP:FlushText() end)
        end
    end)
    box:HookScript("OnEditFocusLost", function() DP:FlushText() end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not multi then box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end) end
    s.Box, s.Bg = box, bg
end

function DP:FlushText()
    local p = self.pendingText
    if not p then return end
    self.pendingText = nil
    for save, text in pairs(p) do
        local ok, err = save(text)
        if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
    end
end

-- Contact: Discord name and a note. Yours, or anyone's for officers (for
-- guildmates without the addon).
function DP:BuildEditContact(parent)
    local s = NewSection(parent, "Contact")
    local PF = ns.Profile
    EditText(s, PF.DISCORD_MAX, 26, false, function(text)
        local e = DP.entry
        if not e then return true end
        return PF:SetContact(e.full, text, nil)
    end)
    s.Line:SetPoint("RIGHT", s.Count, "LEFT", -6, 0)
    s.DiscordBox, s.DiscordBg, s.DiscordCount = s.Box, s.Bg, s.Count
    local dl = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dl:SetPoint("TOPLEFT", s.Bg, "BOTTOMLEFT", 0, -3)
    dl:SetText("Discord name")
    -- second box: the note, under the first
    local holder = CreateFrame("Frame", nil, s)
    holder:SetPoint("TOPLEFT", 0, -22 - 26 - 18)
    holder:SetSize(INNER, 22 + 26)
    EditText(holder, PF.CONTACT_NOTE_MAX, 26, false, function(text)
        local e = DP.entry
        if not e then return true end
        return PF:SetContact(e.full, nil, text)
    end)
    holder.Bg:ClearAllPoints()
    holder.Bg:SetPoint("TOPLEFT", 0, -2)
    holder.Count:ClearAllPoints()
    holder.Count:SetPoint("TOPRIGHT", s.DiscordCount, "TOPRIGHT", 0, -(26 + 18))
    s.NoteBox = holder.Box
    s.Hint = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Hint:SetPoint("TOPLEFT", holder.Bg, "BOTTOMLEFT", 0, -3)
    s.Hint:SetText("Contact note: BattleTag, timezone, best way to reach you. Seen by the guild.")
    s:SetHeight(22 + 26 + 18 + 2 + 26 + 18)
    return s
end

------------------------------------------------------------------------
-- Edit mode: main & alts (officers) and specialization
------------------------------------------------------------------------
function DP:BuildAltSection(parent)
    local s = NewSection(parent, "Main & Alts")
    s.AltLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.AltLabel:SetPoint("TOPLEFT", 0, -22)
    s.AltLabel:SetText("Alt of")
    s.MainLink = NameLink(s)
    s.MainLink:SetPoint("LEFT", s.AltLabel, "RIGHT", 6, 0)
    s.MainLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.MainLabel:SetPoint("TOPLEFT", 0, -22)
    s.MainLabel:SetText("Main character")
    s.AltsTitle = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.altRows = {}
    s.NoAlts = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.NoAlts:SetText("No alts linked yet.")
    s.Primary = W.Button(s, "Mark as Alt", 140, 22)
    s.Secondary = W.Button(s, "Add Alt", 140, 22)
    s.Tertiary = W.Button(s, "Unlink", 140, 22)
    self.alt = s
end

function DP:PickMainFor(full)
    ns.MemberPicker:Open({
        title = "Main of " .. ns.ShortName(full),
        exclude = { [full] = true },
        onPick = function(main)
            local ok, err = ns.DB:SetMain(full, main)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end,
    })
end

function DP:PickAltFor(main)
    local exclude = { [main] = true }
    for _, a in ipairs(ns.DB:GetAltsOf(main)) do exclude[a] = true end
    ns.MemberPicker:Open({
        title = "Add Alt to " .. ns.ShortName(main),
        exclude = exclude,
        onPick = function(alt)
            local ok, err = ns.DB:SetMain(alt, main)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end,
    })
end

local function AltRow(s, i)
    local r = s.altRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, s)
    r:SetSize(INNER, 20)
    r.Link = NameLink(r)
    r.Link:SetPoint("LEFT", 8, 0)
    r.Info = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.Info:SetPoint("LEFT", r.Link, "RIGHT", 6, 0)
    r.Remove = SmallX(r, "Unlink this alt")
    r.Remove:SetPoint("RIGHT", 0, 0)
    r.Remove:SetScript("OnClick", function() ns.DB:ClearMain(r.full) end)
    s.altRows[i] = r
    return r
end

function DP:RefreshAlts(e)
    local s = self.alt
    local full = e.full
    local y
    s.AltLabel:SetShown(e.isAlt)
    s.MainLink:SetShown(e.isAlt)
    s.MainLabel:SetShown(not e.isAlt)
    s.AltsTitle:Hide()
    s.NoAlts:Hide()
    for _, r in ipairs(s.altRows) do r:Hide() end
    if e.isAlt then
        s.MainLink:SetCharacter(e.main)
        y = -46
        s.Primary:SetText("Change Main")
        s.Primary:SetScript("OnClick", function() DP:PickMainFor(full) end)
        s.Secondary:SetText("Make This Main")
        s.Secondary:SetScript("OnClick", function() ns.DB:MakeMain(full) end)
        s.Tertiary:SetText("Unlink")
        s.Tertiary:SetScript("OnClick", function() ns.DB:ClearMain(full) end)
        s.Tertiary:Show()
    else
        y = -42
        if #e.alts > 0 then
            s.AltsTitle:SetText(#e.alts == 1 and "1 alt" or (#e.alts .. " alts"))
            s.AltsTitle:ClearAllPoints()
            s.AltsTitle:SetPoint("TOPLEFT", 0, y)
            s.AltsTitle:Show()
            y = y - 16
            for i, altFull in ipairs(e.alts) do
                local r = AltRow(s, i)
                r.full = altFull
                r.Link:SetCharacter(altFull)
                local ae = ns.Roster.byName[altFull]
                r.Info:SetText(ae and ("%d %s"):format(ae.level, ae.className) or "")
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, y)
                r:Show()
                y = y - 20
            end
        else
            s.NoAlts:ClearAllPoints()
            s.NoAlts:SetPoint("TOPLEFT", 0, y)
            s.NoAlts:Show()
            y = y - 16
        end
        y = y - 6
        s.Primary:SetText("Add Alt")
        s.Primary:SetScript("OnClick", function() DP:PickAltFor(full) end)
        s.Secondary:SetText("Mark as Alt of...")
        s.Secondary:SetScript("OnClick", function() DP:PickMainFor(full) end)
        s.Tertiary:Hide()
    end
    s.Primary:ClearAllPoints()
    s.Primary:SetPoint("TOPLEFT", 0, y)
    s.Secondary:ClearAllPoints()
    s.Secondary:SetPoint("LEFT", s.Primary, "RIGHT", 8, 0)
    y = y - 24
    if s.Tertiary:IsShown() then
        s.Tertiary:ClearAllPoints()
        s.Tertiary:SetPoint("TOPLEFT", 0, y)
        y = y - 24
    end
    s:SetHeight(-y)
end

function DP:BuildSpecSection(parent)
    local s = NewSection(parent, "Specialization")
    s:SetHeight(52)
    s.Icon = s:CreateTexture(nil, "ARTWORK")
    s.Icon:SetSize(28, 28)
    s.Icon:SetPoint("TOPLEFT", 0, -20)
    s.Value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.Value:SetPoint("TOPLEFT", s.Icon, "TOPRIGHT", 8, -1)
    s.Value:SetPoint("RIGHT", -86, 0)
    s.Value:SetJustifyH("LEFT")
    s.Source = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Source:SetPoint("TOPLEFT", s.Value, "BOTTOMLEFT", 0, -3)
    s.Change = W.Button(s, "Change", 78, 22)
    s.Change:SetPoint("TOPRIGHT", 0, -18)
    s.Change:SetScript("OnClick", function(btn) DP:ShowSpecMenu(btn) end)
    self.spec = s
end

-- Role: tank, healer, damage (any of them). The member or officers set it.
function DP:BuildRoleSection(parent)
    local s = NewSection(parent, "Role")
    s:SetHeight(48)
    s.checks = {}
    for i, r in ipairs(D.ROLES) do
        local cb = CreateFrame("CheckButton", nil, s, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", (i - 1) * 110, -20)
        local icon = s:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        W.SetIcon(icon, r.icon)
        local label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetText(r.label)
        cb:SetScript("OnClick", function(self)
            local e = DP.entry
            if not e then return end
            local set = {}
            for key in pairs(e.roles or {}) do set[key] = true end
            set[r.key] = self:GetChecked() and true or nil
            local ok, err = ns.DB:SetRoles(e.full, set)
            if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        end)
        s.checks[r.key] = cb
    end
    W.Tooltip(s.checks.tank, "Tank", "Tick every role this character plays.")
    self.role = s
end

function DP:RefreshRoles(e)
    for key, cb in pairs(self.role.checks) do cb:SetChecked(e.roles and e.roles[key] or false) end
end

function DP:ShowSpecMenu(owner)
    local e = self.entry
    if not e then return end
    local full = e.full
    local m = ns.DB:GetMember(full)
    local items = { { text = "Set specialization", isTitle = true } }
    for _, spec in ipairs(D.CLASS_SPECS[e.classFile] or {}) do
        local icon = D:SpecIcon(e.classFile, spec)
        items[#items + 1] = {
            text = (icon and ("|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t ") or "") .. spec,
            radio = true,
            checked = function() local mm = ns.DB:GetMember(full); return mm and mm.spec == spec end,
            func = function() ns.DB:SetManualSpec(full, spec) end,
        }
    end
    items[#items + 1] = { divider = true }
    items[#items + 1] = {
        text = "Custom...",
        func = function()
            W.Prompt(("Specialization for %s:"):format(e.short), m and m.spec or "", function(text)
                ns.DB:SetManualSpec(full, text)
            end, 24)
        end,
    }
    items[#items + 1] = {
        text = e.hasAddon and "Use their reported spec" or "Clear",
        disabled = not (m and m.spec),
        func = function() ns.DB:SetManualSpec(full, nil) end,
    }
    W.ShowMenu(owner, items)
end

function DP:RefreshSpec(e)
    local sp = self.spec
    local specIcon = D:SpecIcon(e.classFile, e.spec)
    if specIcon then
        W.SetIcon(sp.Icon, specIcon)
        sp.Icon:SetDesaturated(false)
    else
        W.SetClassIcon(sp.Icon, e.classFile)
        sp.Icon:SetDesaturated(not e.spec)
    end
    sp.Value:SetText(e.spec and (e.spec .. (e.dist and ("  |cff9d9d9d(" .. e.dist .. ")|r") or "")) or "|cff9d9d9dUnknown|r")
    if e.specSource == "manual" then
        sp.Source:SetText("Set by hand")
    elseif e.specSource == "addon" then
        sp.Source:SetText("Reported by their addon")
    else
        sp.Source:SetText("Not reported. Use Change to set it.")
    end
    sp.Change:SetShown(ns.DB:CanEditProfile(e.full))
end

------------------------------------------------------------------------
-- Show, edit mode, layout
------------------------------------------------------------------------
function DP:Show(full)
    if not self.frame then return end
    if self.full ~= full then
        self:FlushNote()
        self:FlushText()
        if self.note.Box:HasFocus() then self.note.Box:ClearFocus() end
        self.log.Input:SetText("")
        ns.MemberPicker:Hide()
        if self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
        self.editing = false
    end
    self.full = full
    self.frame:Show()
    self:Refresh(true)
end

function DP:Hide()
    if self.frame then self.frame:Hide() end
end

-- Opens your own profile in Edit mode.
function DP:EditSelf()
    local me = ns.PlayerFullName()
    if not ns.Roster.byName[me] then
        ns:Print("Your profile appears once the guild roster has loaded.")
        return
    end
    ns.UI:OpenTab(ns.UI.TAB_ROSTER)
    ns.RosterView:Select(me)
    self:SetEditing(true)
end

-- May you edit anything on this profile?
function DP:CanEdit(e)
    if not e then return false end
    return e.full == ns.PlayerFullName() or ns.IsOfficer() or ns.DB:CanEditProfile(e.full) or ns.DB:CanEditTags(e.full)
        or ns.DB:CanEditLinks()
end

function DP:SetEditing(on)
    if on and not self:CanEdit(self.entry) then return end
    self:FlushText()
    self:FlushNote()
    self.editing = on and true or false
    if self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
    self:Refresh(true)
end

-- Visible sections in order, for the current mode and tab.
function DP:VisibleSections(e)
    local list = {}
    local function add(s, show) if show ~= false then list[#list + 1] = s end end
    if self.editing then
        add(self.editContact, ns.Profile:CanEditContact(e.full))
        add(self.alt, ns.DB:CanEditLinks())
        add(self.spec)
        add(self.role)
        add(self.tagsEdit, self:LayoutTags(self.tagsEdit, e))
        add(self.prof)
        return list
    end
    add(self.linkLine)
    add(self.contactBox, self:RefreshContactBox(e))
    add(self.tagsRead, self:LayoutTags(self.tagsRead, e))
    add(self.schedule, self:RefreshSchedule(e))
    add(self.tabs)
    if self.tab == "notes" then
        add(self.note)
    elseif self.tab == "officer" then
        add(self.log); add(self.history)
    else
        add(self.prof)
    end
    return list
end

function DP:Layout(visible)
    visible = visible or self.visible or {}
    self.visible = visible
    local shown = {}
    for _, s in ipairs(visible) do shown[s] = true end
    for _, s in ipairs(self.allSections) do s:SetShown(shown[s] or false) end
    local prev, total = self.header, self.header:GetHeight()
    for _, s in ipairs(visible) do
        s:ClearAllPoints()
        local gap = (s == self.tabs) and (SECTION_GAP + 4) or SECTION_GAP
        if s == self.linkLine or s == self.contactBox or s == self.tagsRead then gap = 8 end
        s:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
        total = total + gap + s:GetHeight()
        prev = s
    end
    self.content:SetHeight(total + 12)
end

function DP:Refresh(forceText)
    local e = self.full and ns.Roster.byName[self.full]
    self.entry = e
    if not e then
        self.frame:Hide()
        return
    end
    if self.editing and not self:CanEdit(e) then self.editing = false end
    local mine = e.full == ns.PlayerFullName()

    W.SetTitle(self.frame, self.editing and (mine and "Editing Your Profile" or ("Editing " .. e.short)) or "Character Profile")
    self.editBtn:SetShown(self:CanEdit(e))
    self.editBtn:SetText(self.editing and "Done" or "Edit")

    self:RefreshHeader(e)
    if self.editing then
        local ec = self.editContact
        if ns.Profile:CanEditContact(e.full) then
            local d, n = ns.Profile:OwnContact(e.full)
            if forceText or not ec.DiscordBox:HasFocus() then ec.DiscordBox:SetText(d) end
            if forceText or not ec.NoteBox:HasFocus() then ec.NoteBox:SetText(n) end
        end
        if ns.DB:CanEditLinks() then self:RefreshAlts(e) end
        self:RefreshSpec(e)
        self:RefreshRoles(e)
    else
        self:RefreshLinkLine(e)
        self:RefreshTabs()
        if self.tab == "notes" then
            local box = self.note.Box
            if forceText or not box:HasFocus() then box:SetText(e.note or "") end
            self:SizeNote()
        elseif self.tab == "officer" then
            self:RefreshLog(e)
            self:RefreshHistory(e)
        end
    end
    self:RefreshProfs(e)

    if e.hasAddon then
        self.footer:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t Uses the addon"
            .. (e.version and (" (" .. e.version .. ")") or "") .. " - synced " .. ns.FormatAgo(e.syncedAt))
    else
        self.footer:SetText("Not running Nootropic Guild Manager. Spec and professions can be set by hand.")
    end

    self:Layout(self:VisibleSections(e))
end
