--[[
    Nootropic Guild Manager - Character profile flyout
    Opens beside the roster (like the default guild member detail frame).
    Everything scrolls: main/alt links, spec, professions, content tags,
    rating, private notes and the officer log.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local DP = {}
ns.DetailPanel = DP

local WIDTH = 336
local INNER = WIDTH - 52 -- scroll child width (room for the scroll bar)
local MAX_PROFS = 6
local SECTION_GAP = 16

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
        ns.MemberPicker:Hide()
        ns.RosterView:ClearSelection()
    end, "closing the profile"))
    self.frame = f

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
    self.sections = {
        self:BuildAltSection(content),
        self:BuildSpecSection(content),
        self:BuildProfSection(content),
        self:BuildTagSection(content),
        self:BuildRatingSection(content),
        self:BuildNoteSection(content),
        self:BuildLogSection(content),
        self:BuildHistorySection(content),
    }

    self.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.footer:SetPoint("BOTTOMLEFT", 14, 10)
    self.footer:SetPoint("BOTTOMRIGHT", -14, 10)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetWordWrap(false)

    ns:On("ROSTER_UPDATED", function()
        if f:IsShown() then ns.Debounce("detail", 0.05, function() DP:Refresh() end) end
    end)
end

local function NewSection(parent, title)
    local s = CreateFrame("Frame", nil, parent)
    s:SetWidth(INNER)
    s.Title, s.Line = W.SectionHeader(s, title)
    s.Title:SetPoint("TOPLEFT", 0, 0)
    return s
end

-- Clickable character name (opens that profile).
local function NameLink(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetSize(14, 14)
    b.Icon:SetPoint("LEFT", 0, 0)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.Text:SetPoint("LEFT", b.Icon, "RIGHT", 5, 0)
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
        self:SetWidth(math.ceil(self.Text:GetStringWidth()) + 22)
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

function DP:BuildHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(INNER, 46)
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
    h.Name:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 8, -2)
    h.Name:SetPoint("RIGHT", 0, 0)
    h.Name:SetJustifyH("LEFT")

    h.Sub = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.Sub:SetPoint("TOPLEFT", h.Name, "BOTTOMLEFT", 0, -3)
    h.Sub:SetPoint("RIGHT", 0, 0)
    h.Sub:SetJustifyH("LEFT")

    h.Status = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.Status:SetPoint("TOPLEFT", h.Sub, "BOTTOMLEFT", 0, -2)
    h.Status:SetPoint("RIGHT", 0, 0)
    h.Status:SetJustifyH("LEFT")

    self.header = h
end

------------------------------------------------------------------------
-- Main & Alts
------------------------------------------------------------------------
function DP:BuildAltSection(parent)
    local s = NewSection(parent, "Main & Alts")

    -- Shown when this character is an alt
    s.AltLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.AltLabel:SetPoint("TOPLEFT", 0, -22)
    s.AltLabel:SetText("Alt of")
    s.MainLink = NameLink(s)
    s.MainLink:SetPoint("LEFT", s.AltLabel, "RIGHT", 6, 0)

    -- Shown when this character is a main
    s.MainLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.MainLabel:SetPoint("TOPLEFT", 0, -22)
    s.MainLabel:SetText("Main character")
    s.AltsTitle = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.altRows = {}
    s.NoAlts = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.NoAlts:SetText("No alts linked yet.")

    -- Buttons (row 1 and row 2)
    s.Primary = W.Button(s, "Mark as Alt", 128, 22)
    s.Secondary = W.Button(s, "Add Alt", 128, 22)
    s.Tertiary = W.Button(s, "Unlink", 128, 22)

    self.alt = s
    return s
end

function DP:PickMainFor(full)
    local exclude = { [full] = true }
    ns.MemberPicker:Open({
        title = "Main of " .. ns.ShortName(full),
        exclude = exclude,
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
                r.Remove:SetShown(ns.DB:CanEditLinks())
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

    -- Linking mains and alts is for officers; everyone else just sees the links.
    local canLink = ns.DB:CanEditLinks()
    s.Primary:SetShown(canLink)
    s.Secondary:SetShown(canLink)
    if not canLink then
        s.Tertiary:Hide()
        s:SetHeight(-y + 4)
        return
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

------------------------------------------------------------------------
-- Specialization
------------------------------------------------------------------------
function DP:BuildSpecSection(parent)
    local s = NewSection(parent, "Specialization")
    s:SetHeight(52)

    s.Icon = s:CreateTexture(nil, "ARTWORK")
    s.Icon:SetSize(30, 30)
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
    return s
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

------------------------------------------------------------------------
-- Professions
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
    r.Name:SetWidth(96)
    r.Name:SetJustifyH("LEFT")
    r.Name:SetWordWrap(false)

    local barFrame = CreateFrame("Frame", nil, r, "BackdropTemplate")
    barFrame:SetSize(126, 16)
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

    r.Synced = r:CreateTexture(nil, "OVERLAY")
    r.Synced:SetSize(12, 12)
    r.Synced:SetPoint("RIGHT", -1, 0)
    r.Synced:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

    r:SetScript("OnClick", function() DP:EditProfRank(r.prof) end)
    r:SetScript("OnEnter", function(self)
        local p = self.prof
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(p.name)
        if p.source == "addon" then
            GameTooltip:AddLine("Reported by their Nootropic Guild Manager addon.", 0.4, 1, 0.4, true)
        else
            GameTooltip:AddLine("Added manually. Click to set the skill level.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

function DP:BuildProfSection(parent)
    local s = NewSection(parent, "Professions")
    s.Line:SetPoint("RIGHT", s, "RIGHT", -60, 0)

    s.Add = W.Button(s, "Add", 54, 18)
    s.Add:SetPoint("TOPRIGHT", 0, 2)
    s.Add:SetScript("OnClick", function(btn) DP:ShowAddProfMenu(btn) end)

    s.rows = {}
    for i = 1, MAX_PROFS do
        local r = BuildProfRow(s)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 23)
        r:Hide()
        s.rows[i] = r
    end

    s.Empty = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Empty:SetPoint("TOPLEFT", 0, -22)
    s.Empty:SetWidth(INNER)
    s.Empty:SetJustifyH("LEFT")
    s.Empty:SetText("No professions known yet. Use Add, or have them install Nootropic Guild Manager.")

    self.prof = s
    return s
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

------------------------------------------------------------------------
-- Tags (shared with the guild)
------------------------------------------------------------------------
function DP:BuildTagSection(parent)
    local s = NewSection(parent, "Tags")
    s.pills = {}
    self.tags = s
    return s
end

function DP:LayoutTags(e)
    local s = self.tags
    local m = ns.DB:GetMember(e.full)
    local set = (m and m.tags) or {}
    local x, y, rowH = 0, -22, 22
    local tags = ns.DB:GetTags()
    for i, tag in ipairs(tags) do
        local p = s.pills[i]
        if not p then
            p = W.Pill(s, 18, 16)
            p:SetScript("OnClick", function(self)
                if DP.entry and self.tag and ns.DB:CanEditTags(DP.entry.full) then
                    ns.DB:SetTag(DP.entry.full, self.tag.id)
                    ns.PlaySound("U_CHAT_SCROLL_BUTTON")
                end
            end)
            p:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.tag and self.tag.name or "")
                if DP.entry and ns.DB:CanEditTags(DP.entry.full) then
                    GameTooltip:AddLine("Click to toggle. Shared with everyone in the guild using the addon.", 1, 1, 1, true)
                else
                    GameTooltip:AddLine("Officers set tags (members can set their own).", 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end)
            p:SetScript("OnLeave", function() GameTooltip:Hide() end)
            s.pills[i] = p
        end
        p:SetTag(tag, set[tag.id] and true or false)
        local w = p:GetWidth()
        if x > 0 and x + w > INNER then
            x = 0
            y = y - rowH
        end
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", x, y)
        p:Show()
        x = x + w + 4
    end
    for i = #tags + 1, #s.pills do s.pills[i]:Hide() end
    s:SetHeight(-y + rowH)
end

------------------------------------------------------------------------
-- Rating
------------------------------------------------------------------------
function DP:BuildRatingSection(parent)
    local s = NewSection(parent, "Rating")
    s:SetHeight(48)
    s.Stars = W.Stars(s, 22, true, function(v)
        if DP.entry then ns.DB:SetRating(DP.entry.full, v) end
    end)
    s.Stars:SetPoint("TOPLEFT", 0, -22)
    s.Label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.Label:SetPoint("LEFT", s.Stars, "RIGHT", 12, 0)
    W.Tooltip(s.Stars, "How well do they play their class?", "Click a star to rate. Right-click to clear.")
    self.rating = s
    return s
end

------------------------------------------------------------------------
-- Private notes (only you; grows with its text)
------------------------------------------------------------------------
local NOTE_MIN_H = 44

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

    self.note = s
    self:SizeNote()
    return s
end

function DP:SizeNote()
    local s = self.note
    if not s then return end
    local h = math.max(NOTE_MIN_H, (s.Box:GetHeight() or 0) + 14)
    if s.Bg:GetHeight() ~= h then
        s.Bg:SetHeight(h)
        s:SetHeight(22 + h)
        if self.entry then self:Layout() end
    else
        s:SetHeight(22 + h)
    end
end

function DP:FlushNote()
    local p = self.pendingNote
    if p then
        self.pendingNote = nil
        ns.DB:SetNote(p.full, p.text)
    end
end

------------------------------------------------------------------------
-- Officer log (timestamped, visible and synced to officers only)
------------------------------------------------------------------------
function DP:BuildLogSection(parent)
    local s = NewSection(parent, "Officer Log")
    s.Hint = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Hint:SetPoint("LEFT", s.Title, "RIGHT", 6, 0)
    s.Hint:SetText("officers only")
    s.Line:SetPoint("LEFT", s.Hint, "RIGHT", 6, 0)

    local input = CreateFrame("EditBox", "NootropicGMLogInput", s, "InputBoxTemplate")
    input:SetSize(INNER - 64, 20)
    input:SetPoint("TOPLEFT", 6, -22)
    input:SetAutoFocus(false)
    input:SetMaxLetters(D.MAX_LOG_LENGTH)
    input:SetFontObject("GameFontHighlightSmall")
    s.Input = input

    s.Add = W.Button(s, "Add", 54, 22)
    s.Add:SetPoint("TOPRIGHT", 0, -21)

    local function Submit()
        local e = DP.entry
        if not e then return end
        local entry = ns.DB:AddLogEntry(e.full, input:GetText())
        if entry then
            ns.Comm:SendLog(e.full, entry)
            input:SetText("")
        end
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
    return s
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
            local deleted = ns.DB:DeleteLogEntry(e.full, entry.id)
            if deleted then ns.Comm:SendLog(e.full, deleted) end
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

------------------------------------------------------------------------
-- Show / refresh
------------------------------------------------------------------------
function DP:Show(full)
    if not self.frame then return end
    if self.full ~= full then
        self:FlushNote()
        if self.note.Box:HasFocus() then self.note.Box:ClearFocus() end
        self.log.Input:SetText("")
        ns.MemberPicker:Hide()
        if self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
    end
    self.full = full
    self.frame:Show()
    self:Refresh(true)
end

function DP:Hide()
    if self.frame then self.frame:Hide() end
end

------------------------------------------------------------------------
-- Change history (officers only): every synced change to this character
------------------------------------------------------------------------
local HISTORY_MAX = 15

function DP:BuildHistorySection(parent)
    local s = NewSection(parent, "Change History")
    s.Hint = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Hint:SetPoint("LEFT", s.Title, "RIGHT", 6, 0)
    s.Hint:SetText("officers only")
    s.Line:SetPoint("LEFT", s.Hint, "RIGHT", 6, 0)
    s.rows = {}
    s.Empty = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.Empty:SetText("No recorded changes yet.")
    s.All = W.Button(s, "View all in Audit", 140, 20)
    s.All:SetScript("OnClick", function()
        if not DP.entry then return end
        local full = DP.entry.full
        ns.UI:SelectTab(ns.UI.TAB_AUDIT)
        ns.AuditView:SetMember(full)
    end)
    ns:On("AUDIT_CHANGED", function()
        if DP.frame and DP.frame:IsShown() and DP.entry then ns.Debounce("detailhistory", 0.2, function() DP:Refresh() end) end
    end)
    self.history = s
    return s
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
    local groups = ns.Audit:Group(entries) -- changes saved together share one heading
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
    s.All:SetText(#groups > HISTORY_MAX and ("View all %d in Audit"):format(#entries) or "View in Audit tab")
    s:SetHeight(-y + 28)
end

function DP:Layout()
    local prev, total = self.header, self.header:GetHeight()
    for _, s in ipairs(self.sections) do
        if s:IsShown() then
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SECTION_GAP)
            total = total + SECTION_GAP + s:GetHeight()
            prev = s
        end
    end
    self.content:SetHeight(total + 12)
end

function DP:Refresh(forceNote)
    local e = self.full and ns.Roster.byName[self.full]
    self.entry = e
    if not e then
        self.frame:Hide()
        return
    end

    -- Header
    local h = self.header
    W.SetClassIcon(h.Icon, e.classFile)
    h.Name:SetText(e.short)
    h.Name:SetTextColor(ns.ClassColor(e.classFile))
    h.Sub:SetText(("Level %d %s  |cff9d9d9d-|r  %s"):format(e.level, e.className, e.rank))
    if e.online then
        h.Status:SetText("|cff40ff40Online|r  " .. e.zone)
    else
        h.Status:SetText("|cff9d9d9dOffline - last seen " .. ns.FormatLastSeen(e.lastOnline) .. " ago|r")
    end

    self:RefreshAlts(e)

    -- Spec
    local sp = self.spec
    local specIcon = D:SpecIcon(e.classFile, e.spec)
    if specIcon then
        W.SetIcon(sp.Icon, specIcon)
        sp.Icon:SetDesaturated(false)
    else
        W.SetClassIcon(sp.Icon, e.classFile)
        sp.Icon:SetDesaturated(not e.spec)
    end
    if e.spec then
        sp.Value:SetText(e.spec .. (e.dist and ("  |cff9d9d9d(" .. e.dist .. ")|r") or ""))
    else
        sp.Value:SetText("|cff9d9d9dUnknown|r")
    end
    if e.specSource == "manual" then
        sp.Source:SetText("Set manually")
    elseif e.specSource == "addon" then
        sp.Source:SetText("Reported by their addon")
    else
        sp.Source:SetText("Not reported. Use Change to set it.")
    end

    -- Professions
    local ps = self.prof
    for i = 1, MAX_PROFS do
        local r, p = ps.rows[i], e.profs[i]
        r.prof = p
        if p then
            W.SetIcon(r.Icon, D:ProfIcon(p))
            r.Name:SetText(p.name)
            local max = (p.max and p.max > 0) and p.max or D.PROF_MAX_RANK
            r.Bar:SetMinMaxValues(0, max)
            r.Bar:SetValue(p.rank or 0)
            if p.rank and p.rank > 0 then
                r.BarText:SetText(p.max and p.max > 0 and (p.rank .. " / " .. p.max) or tostring(p.rank))
            else
                r.BarText:SetText("|cff9d9d9dset level|r")
            end
            r.Remove:SetShown(p.source == "manual")
            r.Synced:SetShown(p.source == "addon")
            r:Show()
        else
            r:Hide()
        end
    end
    local shownProfs = math.min(#e.profs, MAX_PROFS)
    ps.Empty:SetShown(shownProfs == 0)
    ps:SetHeight(20 + math.max(1, shownProfs) * 23 + (shownProfs == 0 and 10 or 0))

    self:LayoutTags(e)

    -- Rating: officers only
    self.rating:SetShown(ns.DB:CanRate())
    self.rating.Stars:SetValue(e.rating)
    self.rating.Label:SetText("")

    -- Editing controls follow permissions
    local canProfile = ns.DB:CanEditProfile(e.full)
    self.spec.Change:SetShown(canProfile)
    self.prof.Add:SetShown(canProfile)
    for _, r in ipairs(self.prof.rows) do
        if r.prof then r.Remove:SetShown(canProfile and r.prof.source == "manual") end
    end

    -- Private notes: never overwrite what the user is typing
    local box = self.note.Box
    if forceNote or not box:HasFocus() then
        box:SetText(e.note or "")
    end
    self:SizeNote()

    -- Officer log
    local officer = ns.IsOfficer()
    self.log:SetShown(officer)
    if officer then self:RefreshLog(e) end

    -- Change history: officers only, at the bottom
    self.history:SetShown(officer)
    if officer then self:RefreshHistory(e) end

    -- Footer
    if e.hasAddon then
        self.footer:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t Uses Nootropic Guild Manager - synced " .. ns.FormatAgo(e.syncedAt))
    else
        self.footer:SetText("Not running Nootropic Guild Manager. Spec and professions can be set by hand.")
    end

    self:Layout()
end
