--[[
    Nootropic Guild Manager - Options
    Pages in the game's Options > AddOns list (also opened by /ngm options,
    or right-clicking the minimap button):

      Nootropic Guild Manager   appearance, minimap button, reset, sync and commands
        Recruiting              /who whisper button, sending, auto-invite, Do Not Whisper
        Officers                permissions (Guild Master), audit history
        About                   what the addon does, credits, links

    O:Open(key) opens one: nil (main), "recruiting", "officers" or "about".
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local O = {}
ns.Options = O

local PANEL_NAME = "Nootropic Guild Manager"
O.pages = {}   -- key -> outer frame
O.subcats = {} -- key -> settings category

------------------------------------------------------------------------
-- Layout: each page stacks rows top to bottom with a cursor
------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function Layout:Header(text)
    local title, line = W.SectionHeader(self.panel, text)
    title:SetPoint("TOPLEFT", 16, self.y)
    line:SetPoint("RIGHT", self.panel, "RIGHT", -16, 0)
    self.y = self.y - 26
    return title
end

-- Text blocks wrap at a fixed width. Pages are built while hidden, before
-- the game has sized them, so a block can't measure its own wrapped height;
-- an invisible copy on UIParent (always laid out) measures it instead. The
-- settings canvas is ~635 wide on Forever (SettingsPanel 920), so 564 fits.
local TEXT_W = 564
local measure
local function TextHeight(text, font, width)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY")
        measure:SetWordWrap(true)
        measure:SetJustifyH("LEFT")
        -- shown but invisible and off screen, so it's always laid out
        measure:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 200, -200)
        measure:SetAlpha(0)
    end
    measure:SetFontObject(font)
    measure:SetSpacing(3)
    measure:SetWidth(width or TEXT_W)
    measure:SetText(text ~= "" and text or " ")
    return math.ceil(measure:GetStringHeight() or 14)
end

-- A checkbox with an optional hint under it (wraps, like Text).
local HINT_INDENT = 26 -- the label starts 26 further right than text blocks
function Layout:Check(text, hint, onClick)
    local cb = CreateFrame("CheckButton", nil, self.panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 14, self.y)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    label:SetFontObject("NGMFontText")
    label:SetText(text)
    local hintH = 0
    if hint then
        local h = self.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
        h:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        h:SetWidth(TEXT_W - HINT_INDENT)
        h:SetJustifyH("LEFT")
        h:SetWordWrap(true)
        h:SetSpacing(3)
        h:SetText(hint)
        cb.Hint = h
        hintH = TextHeight(hint, "NGMFontDimSmall", TEXT_W - HINT_INDENT)
    end
    cb:SetScript("OnClick", function(b) onClick(b:GetChecked() and true or false) end)
    self.y = self.y - (hint and (30 + hintH) or 30)
    return cb
end

-- A block of text (wraps at TEXT_W). Text set later with SetText should be
-- no longer than the text it was built with, or it would run into what's below.
function Layout:Text(text, font, gap)
    font = font or "NGMFontTextSmall"
    local fs = self.panel:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", 18, self.y)
    fs:SetWidth(TEXT_W)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
    fs:SetText(text)
    self.y = self.y - math.max(14, TextHeight(text, font)) - (gap or 8)
    return fs
end

-- Reserves `height` and returns the top of that row.
function Layout:Row(height)
    local y = self.y
    self.y = self.y - height
    return y
end

function Layout:Space(n) self.y = self.y - (n or 10) end

function Layout:Finish() self.panel:SetHeight(-self.y + 30) end

-- A scrolling page with a title. Returns the outer frame and a layout.
local function NewPage(key, name, subtitle)
    local outer = CreateFrame("Frame", "NootropicGMOptions" .. key, UIParent)
    outer.name = name
    outer:Hide()
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMOptionsScroll" .. key, outer, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(600, 800)
    scroll:SetScrollChild(panel)
    outer:SetScript("OnSizeChanged", function(_, w) panel:SetWidth(math.max(400, (w or 600) - 30)) end)
    outer:SetScript("OnShow", function(f)
        O:Refresh()
    end)
    O.pages[key] = outer

    -- the addon's own logo, whatever the icon choice (this is about the addon)
    local logo = ns.Brand:Attach(panel, 36, { "TOPLEFT", panel, "TOPLEFT", 16, -14 })
    local title = panel:CreateFontString(nil, "OVERLAY", "NGMFontTitle")
    title:SetPoint("TOPLEFT", logo.Slot, "TOPRIGHT", 10, -2)
    title:SetText(key == "main" and PANEL_NAME or (PANEL_NAME .. "  |cffffffff-  " .. name .. "|r"))
    local sub = panel:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(subtitle)
    outer.Sub = sub
    O.logos = O.logos or {}
    O.logos[#O.logos + 1] = logo
    return outer, setmetatable({ panel = panel, y = -66 }, Layout)
end

-- Small dropdown-style button that picks one of D.MINIMAP_ACTIONS.
local function ActionPicker(L, label, key)
    local y = L:Row(28)
    local text = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    text:SetPoint("TOPLEFT", 42, y - 4)
    text:SetText(label)
    local b = W.Button(L.panel, "", 200, 22)
    b:SetPoint("TOPLEFT", 150, y)
    b:SetScript("OnClick", function(self)
        local items = { { text = label, isTitle = true } }
        for _, a in ipairs(D.MINIMAP_ACTIONS) do
            items[#items + 1] = {
                text = D:MinimapActionLabel(a.key), radio = true,
                checked = function() return ns.DB:Settings().minimap[key] == a.key end,
                func = function()
                    ns.DB:Settings().minimap[key] = a.key
                    O:Refresh()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    b.key = key
    return b
end

-- Six small word boxes (keywords, Do Not Whisper words), three per row.
local function WordBoxes(L, maxLetters, onChange)
    local boxes = {}
    local top = L:Row(54)
    for i = 1, D.MAX_KEYWORDS do
        local eb = CreateFrame("EditBox", nil, L.panel, "InputBoxTemplate")
        eb:SetSize(120, 20)
        eb:SetAutoFocus(false)
        eb:SetFontObject("NGMFontTextSmall")
        eb:SetMaxLetters(maxLetters)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        eb:SetPoint("TOPLEFT", 26 + col * 132, top - row * 26)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:HookScript("OnTextChanged", function(self, user) if user then onChange(i, ns.Trim(self:GetText())) end end)
        boxes[i] = eb
    end
    return boxes
end

local function RecruitChanged() ns:Fire("RECRUITS_CHANGED") end

------------------------------------------------------------------------
-- Main page: appearance, minimap button, reset, about
------------------------------------------------------------------------
function O:BuildMain()
    local outer, L = NewPage("main", PANEL_NAME,
        ("Version %s  -  /ngm to open  -  more settings on the Recruiting and Officers pages below this one"):format(ns.version))
    self.panel = outer

    L:Header("How It Works")
    L:Text(("Open the window with |cffffffff/ngm|r or the minimap button. Its tabs: " .. ns.GOLD .. "Find|r (search the guild), " .. ns.GOLD .. "Play Together|r (who's around near your level), " .. ns.GOLD .. "Recruitment|r and, for officers, " .. ns.GOLD .. "Audit|r. Click anyone for their profile: spec, professions and recipes, raid readiness, contact info and your private notes."))
    L:Text(("Everyone running the addon shares what their own copy knows: spec, professions, recipes (when they open a profession window), raid attunements and when they usually play. The more of the guild uses it, the more it knows. Private notes never leave your computer. The " .. ns.GOLD .. "About|r page below has links and credits."), "NGMFontDimSmall")
    L:Space(4)

    L:Header("Appearance")
    self.addonCountCheck = L:Check("Show how many guildmates use the addon",
        "The \"x using ... Guild Manager\" text at the bottom of the window.", function(on)
            ns.DB:Settings().showAddonCount = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    self.communitiesCheck = L:Check("Shortcut on the Guild & Communities window",
        "A side tab with the addon icon.", function(on) ns.Communities:SetEnabled(on) end)
    self.blizzRosterCheck = L:Check("Show alts and profiles on the Guild roster",
        "On the game's Guild & Communities roster: this addon's details in the tooltip, and Profile and Main / Alt in the right-click menu. Alt+click a member for their profile.",
        function(on) ns.GuildRoster:SetEnabled(on) end)

    L:Space(4)

    L:Header("Sharing  |cff9d9d9d(what only your copy knows)|r")
    self.shareRecipesCheck = L:Check("Share my recipes",
        "Recipes you've learned, so guildmates can find you in Who Can Craft?. Shared when you open a profession window. Off: your recipes are cleared.",
        function(on) ns.Sharing:Set("recipes", on) end)
    self.learnCheck = L:Check("Learn when I usually play",
        "Notes the hour every 10 minutes while you play (last 4 weeks, this computer only) and shares just the summary, shown as \"Usually online\" on your profile. Off: nothing is noted or shared. (This character.)",
        function(on) ns.Profile:SetLearn(on) end)
    L:Text("Only what comes from your own copy of the addon has a switch. Your spec, professions, statistics (never gold) and guild chat time (never the words) are always shared: they're public anyway, from Blizzard and the game.", "NGMFontDimSmall")
    local wy = L:Row(30)
    local tour = W.Button(L.panel, "Show the Welcome Tour", 190, 24, "alt")
    tour:SetPoint("TOPLEFT", 18, wy)
    tour:SetScript("OnClick", function() ns.Welcome:Open() end)
    W.Tooltip(tour, "Welcome tour", "The first-launch walkthrough again: what each tab does, your sharing choices, your profile basics (and permissions, for the Guild Master). Also /ngm welcome.")
    L:Space(4)

    -- Install reminder: the whisper "Remind to install the addon" sends
    L:Header("Install Reminder")
    L:Text(("What guildmates without the addon get when you click " .. ns.GOLD .. "Remind to install the addon|r on their profile or right-click menu. ")
        .. (ns.GOLD .. "$first|r, " .. ns.GOLD .. "$name|r and " .. ns.GOLD .. "$guild|r are filled in. Add your Discord invite if you'd like it to cover that too. Saved as you type."))
    local ry = L:Row(84)
    local ef, box = W.ScrollEditor(L.panel, 255)
    ef:SetPoint("TOPLEFT", 22, ry)
    ef:SetSize(TEXT_W - 8, 70)
    box:SetFontObject("NGMFontTextSmall")
    box:SetWidth(TEXT_W - 26)
    self.reminderBox = box
    local count = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    count:SetJustifyH("LEFT")
    self.reminderCount = count
    local function update()
        count:SetText(ns.Recruit:LengthText(box:GetText() ~= "" and box:GetText() or ns.InstallReminder.DEFAULT)
            .. (box:GetText() == "" and "  (empty: the default text is used)" or ""))
    end
    box:HookScript("OnTextChanged", function(eb, user)
        if user then ns.InstallReminder:SetText(eb:GetText()) end
        update()
    end)
    local cy = L:Row(26)
    local default = W.Button(L.panel, "Default Text", 110, 22, "alt")
    default:SetPoint("TOPLEFT", 18, cy)
    default:SetScript("OnClick", function()
        ns.InstallReminder:SetText("")
        box:SetText(ns.InstallReminder.DEFAULT)
        box:ClearFocus()
    end)
    count:SetPoint("LEFT", default, "RIGHT", 10, 0)
    L:Space(4)

    L:Header("Minimap Button")
    self.minimapCheck = L:Check("Show minimap button", nil, function(on) ns.Minimap:SetShown(on) end)
    self.clickPickers = {
        ActionPicker(L, "Left-click", "left"),
        ActionPicker(L, "Right-click", "right"),
        ActionPicker(L, "Shift-click", "shift"),
    }
    L:Space(8)

    L:Header("Reset")
    y = L:Row(32)
    local resetWin = W.Button(L.panel, "Window Size and Position", 190, 24, "alt")
    resetWin:SetPoint("TOPLEFT", 18, y)
    resetWin:SetScript("OnClick", function()
        ns.UI:ResetPosition()
        ns:Print("Window size and position reset.")
    end)
    local resetCols = W.Button(L.panel, "List Columns", 140, 24, "alt")
    resetCols:SetPoint("LEFT", resetWin, "RIGHT", 8, 0)
    resetCols:SetScript("OnClick", function()
        W.Confirm("Reset the columns of the roster and the recruitment list to their default order, widths and visibility?", function()
            ns.RosterView:ResetColumns()
            ns.RecruitView.cols:Reset()
            ns:Print("List columns reset to defaults.")
        end)
    end)
    W.Tooltip(resetCols, "Reset list columns", "Default column order, widths and which columns are shown, on the roster and the recruitment list.")
    L:Space(6)

    L:Header("Sync and Commands")
    self.syncStatus = L:Text("", "NGMFontTextSmall", 6)
    y = L:Row(32)
    local syncNow = W.Button(L.panel, "Sync Now", 110, 24)
    syncNow:SetPoint("TOPLEFT", 18, y)
    syncNow:SetScript("OnClick", function()
        ns.Comm:Report()
        if ns.Sync:CheckAll() then
            ns.Sync.reportLane = "guild"
            ns:Print("Checking with your guild now...")
        end
        O:Refresh()
    end)
    W.Tooltip(syncNow, "Sync now", "Checks your data against your guildmates' and fetches anything you're missing. It also happens by itself each time you log in, and changes are sent as you make them.")
    local open = W.Button(L.panel, "Open Guild Manager", 170, 24)
    open:SetPoint("LEFT", syncNow, "RIGHT", 8, 0)
    open:SetScript("OnClick", function() ns.UI:OpenTab(ns.UI.TAB_ROSTER) end)
    L:Text((ns.GOLD .. "Commands|r\n")
        .. "|cffffffff/ngm|r open or close     |cffffffff/ngm find <text>|r search the roster     |cffffffff/ngm recruit|r recruiting\n"
        .. "|cffffffff/ngm sync|r sync now     |cffffffff/ngm diag|r troubleshooting     |cffffffff/ngm help|r every command", "NGMFontTextSmall")
    L:Finish()
end

------------------------------------------------------------------------
-- Recruiting page
------------------------------------------------------------------------
function O:BuildRecruiting()
    local outer, L = NewPage("recruiting", "Recruiting", "Saved for the guild you're in. Messages and searching are on the Recruitment tab.")
    self.recruitNoGuild = L:Text("|cffff2020Join a guild to change these settings.|r")

    L:Header("/who Window")
    self.whoWhisperCheck = L:Check("Recruitment whisper button on /who results",
        "A button on each player in the game's /who search that sends them your recruitment whisper.",
        function(on) ns.WhoWhisper:SetEnabled(on) end)
    L:Space(4)

    L:Header("Sending Whispers")
    L:Text("The Recruitment tab sends whispers one at a time, at least 12 seconds apart. Blizzard doesn't publish a whisper limit: silences come from players reporting spam, so a friendly message matters more than the pace.")
    local hy = L:Row(30)
    local hourLabel = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    hourLabel:SetPoint("TOPLEFT", 20, hy - 4)
    hourLabel:SetText("Whispers per hour")
    local hourBtn = W.Button(L.panel, "", 160, 22)
    hourBtn:SetPoint("TOPLEFT", 170, hy)
    local function HourText(n) return n == 0 and "No hourly cap (300 max)" or (n .. " per hour") end
    hourBtn:SetScript("OnClick", function(btn)
        local items = { { text = "Whispers per hour", isTitle = true } }
        for _, n in ipairs(ns.Recruit.HOURLY_CHOICES) do
            items[#items + 1] = { text = HourText(n) .. (n == 40 and "  |cff9d9d9d(default)|r" or ""), radio = true,
                checked = function() return (ns.DB:Settings().whisperPerHour or 40) == n end,
                func = function() ns.DB:Settings().whisperPerHour = n; O:Refresh(); RecruitChanged() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(hourBtn, "Whispers per hour", "How many whispers the queue sends in any hour. Saved for all your characters.")
    hourBtn.HourText = HourText
    self.hourButton = hourBtn
    L:Space(4)

    L:Header("Auto-Invite")
    self.autoCheck = L:Check("Invite popup when they reply with a keyword",
        "Only replies from players you whispered from the addon are checked. WoW: Forever only lets you send guild invites yourself, so this pops up an Invite button to click.", function(on)
            local r = ns.Recruit:Settings()
            if r then r.autoInvite = on end
            RecruitChanged()
        end)
    L:Text((ns.GOLD .. "Keywords|r  |cff9d9d9d(whole words, any case)|r"), "NGMFontTextSmall", 4)
    self.keywordBoxes = WordBoxes(L, 24, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.keywords[i] = text end
        RecruitChanged()
    end)
    L:Space(4)

    L:Header("Do Not Whisper")
    self.dnwCheck = L:Check("Add people to the Do Not Whisper list",
        "When someone answers the addon's whisper with one of these words, nobody in the guild whispers or invites them again. Replies after you've whispered them yourself don't count.",
        function(on)
            local r = ns.Recruit:Settings()
            if r then r.dnwEnabled = on end
            RecruitChanged()
        end)
    L:Text((ns.GOLD .. "Words|r  |cff9d9d9d(whole words, any case)|r"), "NGMFontTextSmall", 4)
    self.dnwBoxes = WordBoxes(L, 32, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.dnwWords[i] = text end
        RecruitChanged()
    end)
    local y = L:Row(30)
    self.dnwCount = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.dnwCount:SetPoint("TOPLEFT", 26, y - 5)
    local view = W.Button(L.panel, "View List", 100, 22, "alt")
    view:SetPoint("TOPLEFT", 290, y)
    view:SetScript("OnClick", function() ns.DNWView:Open() end)
    W.Tooltip(view, "Do Not Whisper list", "Who is on it for good, and who was whispered in the last 14 days (with the time left). Shared with everyone in the guild using the addon.")
    self.dnwView = view
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- Officers page
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Permissions (the Guild Master): which ranks may do what
------------------------------------------------------------------------
function O:PermMenu(owner, key)
    local DB = ns.DB
    local items = { { text = "Who may do this", isTitle = true } }
    items[#items + 1] = { text = DB:PermDefaultText(key) .. " (default)", radio = true,
        tooltip = { title = DB:PermDefaultText(key), text = DB:PermDef(key).everyone and "Every rank." or "The ranks the game marks Officer (Guild Control)." },
        checked = function() return DB:PermRanks(key) == nil end,
        func = function()
            local ok, err = DB:SetPermRanks(key, nil)
            if not ok and err then ns:Print("|cffff2020" .. err .. "|r") end
            O:Refresh()
        end }
    items[#items + 1] = { divider = true }
    for _, r in ipairs(DB:GuildRanks()) do
        local gm = r.index == 0
        items[#items + 1] = {
            text = r.name .. (gm and "  |cff9d9d9d(always)|r" or ""),
            checked = function()
                if gm then return true end
                local set = DB:PermRanks(key)
                return set ~= nil and set[r.index] == true
            end,
            func = function()
                if gm then return end
                local set = DB:PermRanks(key) or {}
                set[r.index] = not set[r.index] or nil
                local ok, err = DB:SetPermRanks(key, set)
                if not ok and err then ns:Print("|cffff2020" .. err .. "|r") end
                O:Refresh()
            end,
        }
    end
    W.ShowMenu(owner, items)
end

function O:BuildPermControls(L)
    L:Header("Permissions  |cff9d9d9d(Guild Master, whole guild)|r")
    L:Text("Choose which ranks may do each of these. By default everyone may edit their own profile and the rest is for officers. Pick ranks to hand it to them instead; the Guild Master always can.")
    L:Text("Who's an officer and who may recruit follow the game's own rank settings (Guild Control: Officer, and Invite Member). The Officer Log and the Audit always stay with officers.", "NGMFontDimSmall")
    self.permRows = {}
    for _, perm in ipairs(ns.DB.PERMS) do
        local y = L:Row(28)
        local label = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("TOPLEFT", 20, y - 4)
        label:SetWidth(240)
        label:SetJustifyH("LEFT")
        label:SetText(perm.label)
        local btn = W.Button(L.panel, "", 200, 22)
        btn:SetPoint("TOPLEFT", 270, y)
        btn:SetScript("OnClick", function(self) O:PermMenu(self, perm.key) end)
        W.Tooltip(btn, perm.label, perm.hint)
        self.permRows[#self.permRows + 1] = { key = perm.key, btn = btn }
    end
    self.permNote = L:Text("")
    L:Space(10)
end

function O:RefreshPermControls()
    local gm = ns.DB:IsGuildMaster()
    for _, row in ipairs(self.permRows or {}) do
        row.btn:SetText(ns.DB:PermText(row.key))
        row.btn:SetEnabled(gm)
        row.btn:SetAlpha(gm and 1 or 0.6)
    end
    if self.permNote then
        self.permNote:SetText(gm and "" or "|cffff2020Only the Guild Master can change permissions.|r")
    end
end

function O:BuildOfficers()
    local outer, L = NewPage("officers", "Officers", "For the ranks the game marks Officer.")
    self.officerNote = L:Text("|cffff2020Only officers can change these.|r")

    self:BuildPermControls(L)

    L:Header("Audit History  |cff9d9d9d(your copy)|r")
    L:Text("How long to keep the record of who changed what. Older entries are deleted.")
    local y = L:Row(30)
    self.auditRadios = {}
    for i, days in ipairs({ 30, 60, 90 }) do
        local rb = CreateFrame("CheckButton", nil, L.panel, "UIRadioButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", 20 + (i - 1) * 110, y)
        local label = rb.text or rb.Text
        if type(label) ~= "table" then label = nil end
        if not label then
            label = rb:CreateFontString(nil, "OVERLAY", "NGMFontText")
            label:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        end
        label:SetFontObject("NGMFontText")
        label:SetText(days .. " days")
        rb.days = days
        rb:SetScript("OnClick", function()
            ns.DB:Settings().auditDays = days
            local removed = ns.Sync:PruneAudit() or 0
            if removed > 0 then ns:Print(("Removed %d audit entries older than %d days."):format(removed, days)) end
            O:Refresh()
        end)
        self.auditRadios[i] = rb
    end
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- About page
------------------------------------------------------------------------
-- A read-only box holding a link: click to select it, Ctrl+C to copy.
local function LinkRow(L, link)
    local y = L:Row(46)
    local icon = L.panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 18, y - 4)
    icon:SetTexture(link.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local label = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    label:SetText(link.label)
    local hint = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    hint:SetPoint("LEFT", label, "RIGHT", 8, 0)
    hint:SetText(link.hint or "")
    local box = CreateFrame("EditBox", nil, L.panel, "InputBoxTemplate")
    box:SetSize(360, 20)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -3)
    box:SetAutoFocus(false)
    box:SetText(link.url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(link.url); eb:HighlightText() end end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(eb) eb:HighlightText(0, 0) end)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnKeyDown", function(eb, key)
        if key == "C" and IsControlKeyDown() then C_Timer.After(0.05, function() eb:ClearFocus() end) end
    end)
    W.Tooltip(box, link.label, "Click, then Ctrl+C to copy. Paste it into your browser: the game can't open web links itself.")
    return box
end

function O:BuildAbout()
    local outer, L = NewPage("about", "About", "Who made it, what it does, and where to find more.")

    -- a big banner: the guild's mug, the name, a tagline
    local y = L:Row(92)
    local banner = CreateFrame("Frame", nil, L.panel, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", 14, y)
    banner:SetPoint("RIGHT", L.panel, "RIGHT", -16, 0)
    banner:SetHeight(84)
    banner:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    ns.Theme:Fill(banner, ns.Theme.C.bg1, 0.9)
    ns.Theme:EdgeColor(banner, ns.Theme.C.yellow)
    local logo = ns.Brand:Attach(banner, 64, { "LEFT", banner, "LEFT", 12, 0 })
    O.logos[#O.logos + 1] = logo
    local name = banner:CreateFontString(nil, "OVERLAY", "NGMFontHuge")
    name:SetPoint("TOPLEFT", logo.Slot, "TOPRIGHT", 14, -6)
    name:SetText((ns.GOLD .. "Nootropic|r Guild Manager"))
    local tag = banner:CreateFontString(nil, "OVERLAY", "NGMFontText")
    tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    tag:SetText("Your whole guild, in one window. Built for WoW: Forever.")
    local ver = banner:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    ver:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -5)
    ver:SetText(("Version %s  -  free and open source (MIT)"):format(ns.version))

    L:Space(6)
    L:Header("What's Inside")
    L:Text((ns.GOLD .. "Find|r  search the whole guild by name, class, spec, profession or Discord, with mains and alts grouped together.\n")
        .. (ns.GOLD .. "Play Together|r  who's online near your level right now, and who usually plays at this hour.\n")
        .. (ns.GOLD .. "Overview|r  how many of each class, level and profession, and a heatmap of when the guild plays.\n")
        .. (ns.GOLD .. "Hall of Fame|r  guild leaderboards from everyone's statistics: quests, kills, bosses, deaths and more.\n")
        .. (ns.GOLD .. "Who Can Craft?|r  every recipe your guildmates know, searchable, with online crafters first.\n")
        .. (ns.GOLD .. "Profiles|r  specs, roles, professions, Discord, usual play hours, raid readiness and your private notes.\n")
        .. (ns.GOLD .. "Upcoming Events|r  the guild's dungeons, raids and nights from NGM Peon: when, who's coming and where to sign up.\n")
        .. (ns.GOLD .. "Recruitment|r  friendly whispers to players without a guild, a guild-wide 14-day lockout and a shared Do Not Whisper list.\n")
        .. (ns.GOLD .. "For officers|r  an audit of every change (joins, leaves, promotions, level-ups), an officer log, and Guild Master permissions."))
    L:Text("Everything is shared with guildmates running the addon, so the more of the guild uses it, the more it knows. NGM Peon (optional) carries it to your guild's Discord and back.", "NGMFontDimSmall")

    L:Header("Website")
    L:Text("Click the link, press |cffffffffCtrl+C|r, and paste it into your browser.", "NGMFontDimSmall", 4)
    for _, link in ipairs(D.LINKS) do LinkRow(L, link) end

    L:Header("Credits")
    L:Text(("Maintained by " .. ns.GOLD .. "Keasbeexd|r for " .. ns.GOLD .. "<Nootropic>|r.\n")
        .. ("Built on the original Nootropic Guild Manager by " .. ns.GOLD .. "aigoodandy|r, with permission.\n")
        .. "Bug reports and ideas are welcome: see ngmpeon.app.")
    L:Finish()
    return outer
end

function O:Build()
    self:BuildMain()
    self.subPages = {
        { key = "recruiting", frame = self:BuildRecruiting() },
        { key = "officers", frame = self:BuildOfficers() },
        { key = "about", frame = self:BuildAbout() },
    }
    ns:On("SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("BRAND_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("GUILD_SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("OFFICER_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("RECRUITS_CHANGED", function()
        if O.pages.recruiting and O.pages.recruiting:IsShown() then O:RefreshRecruiting() end
    end)
end

function O:AnyShown()
    for _, page in pairs(self.pages) do if page:IsShown() then return true end end
    return false
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function SetUsable(widget, on)
    widget:SetEnabled(on)
    widget:SetAlpha(on and 1 or 0.45)
end

function O:Refresh()
    local s = ns.DB:Settings()
    for _, logo in ipairs(self.logos or {}) do logo:Apply() end

    -- main
    self.addonCountCheck:SetChecked(s.showAddonCount ~= false)
    self.communitiesCheck:SetChecked(s.communitiesButton ~= false)
    self.blizzRosterCheck:SetChecked(s.blizzRoster ~= false)
    self.learnCheck:SetChecked(ns.Profile:LearnEnabled())
    self.shareRecipesCheck:SetChecked(ns.Sharing:Get("recipes"))
    if not self.reminderBox:HasFocus() then self.reminderBox:SetText(ns.InstallReminder:Text()) end
    self.minimapCheck:SetChecked(not s.minimap.hide)
    for _, b in ipairs(self.clickPickers) do b:SetText(D:MinimapActionLabel(s.minimap[b.key])) end
    self.syncStatus:SetText((ns.GOLD .. "Sync:|r ") .. select(2, ns.Sync:Health()))

    self:RefreshRecruiting()

    -- officers
    local officer = ns.IsOfficer()
    self.officerNote:SetShown(not officer)
    self:RefreshPermControls()
    for _, rb in ipairs(self.auditRadios) do
        rb:SetChecked((s.auditDays or 30) == rb.days)
        SetUsable(rb, officer)
    end
end

function O:RefreshRecruiting()
    local s = ns.DB:Settings()
    self.whoWhisperCheck:SetChecked(s.whoWhisperButton ~= false)
    self.hourButton:SetText(self.hourButton.HourText(s.whisperPerHour or 40))
    local r = ns.Recruit:Settings()
    self.recruitNoGuild:SetShown(r == nil)
    for _, w in ipairs({ self.autoCheck, self.dnwCheck, self.dnwView }) do SetUsable(w, r ~= nil) end
    for _, eb in ipairs(self.keywordBoxes) do eb:SetEnabled(r ~= nil) end
    for _, eb in ipairs(self.dnwBoxes) do eb:SetEnabled(r ~= nil) end
    if not r then
        self.dnwCount:SetText("")
        return
    end
    self.autoCheck:SetChecked(r.autoInvite)
    self.dnwCheck:SetChecked(r.dnwEnabled)
    for i, eb in ipairs(self.keywordBoxes) do
        if not eb:HasFocus() then eb:SetText(r.keywords[i] or "") end
    end
    for i, eb in ipairs(self.dnwBoxes) do
        if not eb:HasFocus() then eb:SetText(r.dnwWords[i] or "") end
    end
    local n = #ns.Recruit:DNWList()
    self.dnwCount:SetText(n == 1 and "1 person on the list" or (n .. " people on the list"))
end

------------------------------------------------------------------------
-- Registration with the game's options window
------------------------------------------------------------------------
function O:Init()
    self:Build()
    local main = self.panel
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(main, PANEL_NAME)
        self.category = category
        if Settings.RegisterCanvasLayoutSubcategory then
            for _, p in ipairs(self.subPages) do
                self.subcats[p.key] = Settings.RegisterCanvasLayoutSubcategory(category, p.frame, p.frame.name)
            end
        end
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(main)
        for _, p in ipairs(self.subPages) do
            p.frame.parent = PANEL_NAME
            InterfaceOptions_AddCategory(p.frame)
        end
    end
end

-- key: nil for the main page, or "recruiting", "officers".
function O:Open(key)
    if not self.panel then return end
    -- the game blocks opening its settings panel in combat (and logs taint)
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("Options can't open during combat. Try again once you're out of combat.")
        return
    end
    if Settings and Settings.OpenToCategory and self.category then
        local cat = key and self.subcats[key] or self.category
        local id = cat.GetID and cat:GetID() or cat.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        local frame = key and self.pages[key] or self.panel
        -- Called twice: the first call only opens the frame on some clients.
        InterfaceOptionsFrame_OpenToCategory(frame)
        InterfaceOptionsFrame_OpenToCategory(frame)
    end
end
