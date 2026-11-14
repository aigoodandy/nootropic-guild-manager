--[[
    Nootropic Guild Manager - Welcome tour
    A short walkthrough shown once on first launch (and to existing users once
    after 2.5.0), reopenable from Options or /ngm welcome:

      welcome   what the addon is
      tour      one page per tab: Find, Play Together, Who Can Craft?,
                Profiles and Raids, Recruitment (ranks that may recruit),
                Audit (officers)
      sharing   the Sharing switches (Services/Sharing.lua)
      profile   your Discord name and roles
      perms     Guild Master only: who may do what
      done      where to find things later

    Settings().welcomeDone records that it was finished or skipped.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local WL = {}
ns.Welcome = WL

local WIDTH, HEIGHT = 600, 440
local BODY_W = WIDTH - 140
local GRAY = "|cff9d9d9d"

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local TAB_ICONS -- filled in from the main window's icons when built

local function Pages()
    local list = {
        { key = "welcome", icon = D.LOGO, full = true, title = "Welcome to Nootropic Guild Manager",
          text = "Your whole guild in one window, built for WoW: Forever.\n\n"
              .. "Every guildmate running the addon shares what their own copy knows: spec, professions, recipes, raid attunements and when they usually play. The more of the guild uses it, the more it knows.\n\n"
              .. "This short tour shows what's where and lets you choose what you share. It takes about a minute." },
        { key = "find", icon = TAB_ICONS[1], title = "Find",
          text = "Search the whole guild by name, class, spec, profession, Discord or notes. Every main is grouped with their alts.\n\n"
              .. ("Type words to search, or use fields like " .. ns.GOLD .. "prof:alchemy|r, " .. ns.GOLD .. "spec:holy|r or " .. ns.GOLD .. "is:online|r. Right-click a column header to choose columns. Click anyone to open their profile.\n\n")
              .. GRAY .. "On the game's own Guild roster you'll also see alt markers, richer tooltips and Profile on the right-click menu.|r" },
        { key = "events", icon = TAB_ICONS[7], title = "Upcoming Events",
          text = "The guild's events for the next 30 days: dungeons, raids and guild nights, with the time (your own), how long, and how many are coming.\n\n"
              .. ("Sign up in " .. ns.GOLD .. "Discord|r, with the buttons on each event's post: the tab says which channel. Events are created on the " .. ns.GOLD .. "NGM Peon dashboard|r.") },
        { key = "overview", icon = TAB_ICONS[5], title = "Overview",
          text = "The guild at a glance: how many of each class, level and profession, counting the people who've played lately.\n\n"
              .. (ns.GOLD .. "When we play|r is a week heatmap from the hours guildmates share: hover a block to see who usually plays then. Click any bar to list those members on the Find tab.") },
        { key = "hof", icon = TAB_ICONS[6], title = "Hall of Fame",
          text = ("Guild leaderboards from everyone's character statistics: quests, kills, dungeon bosses, honorable kills, deaths, flights, fish, hugs and more, plus " .. ns.GOLD .. "Social Butterfly|r, the time spent chatting with guildmates.\n\n")
              .. ("Each card's leader for the month is its " .. ns.GOLD .. "champion|r, shown on the card all next month; titles add up on " .. ns.GOLD .. "Most Champion Wins|r. Each member's own addon shares their numbers (never gold), the same ones Blizzard publishes.") },
        { key = "together", icon = TAB_ICONS[2], title = "Play Together",
          text = "Who to play with right now: guildmates online within a few levels of you (people in your zone first), and guildmates who usually play at this hour.\n\n"
              .. "Usual hours are learned from when people actually play, so this list grows over the first few days." },
        { key = "craft", icon = "Interface\\Icons\\Trade_Alchemy", title = "Who Can Craft It?",
          text = "Every recipe your guildmates know, in one search, with crafters who are online first.\n\n"
              .. ("Open it from the " .. ns.GOLD .. "Who Can Craft?|r button on the Find tab, or type " .. ns.GOLD .. "/ngm craft flask|r.\n\n")
              .. "Your own recipes are shared when you open one of your profession windows, so open each of yours once." },
        { key = "profiles", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", title = "Profiles and Raids",
          text = "Every profile shows spec, roles, professions (and their recipes), Discord, when they usually play, and your own private notes about them, which never leave your computer.\n\n"
              .. ("The " .. ns.GOLD .. "Raids|r tab shows raid readiness: the Onyxia attunement and the Barrow Deeps key, worked out by each member's own addon.") },
    }
    if ns.Recruit:MayRecruit() then
        list[#list + 1] = { key = "recruit", icon = TAB_ICONS[3], title = "Recruitment",
            text = ("Search " .. ns.GOLD .. "/who|r for players without a guild, tick the ones you like, and send friendly whispers one at a time.\n\n")
                .. "Anyone whispered by the guild is locked for 14 days, and anyone who says no goes on the shared Do Not Whisper list, so nobody gets pestered twice.\n\n"
                .. ("When someone replies yes, an Invite prompt shows the " .. ns.GOLD .. "/ginvite|r line to copy and paste: WoW: Forever only accepts invites you type yourself.") }
    end
    if ns.IsOfficer() then
        list[#list + 1] = { key = "audit", icon = TAB_ICONS[4], title = "Audit (officers)",
            text = "Every change across the guild: who changed what and when, plus joins, leaves, kicks, promotions, level-ups and note changes from the guild log.\n\n"
                .. "Profiles also get an Officer tab with the officer log, the character's history, when they joined and since when they've held their rank." }
    end
    list[#list + 1] = { key = "sharing", icon = "Interface\\Icons\\INV_Letter_15", title = "What You Share",
        text = "Two things only your copy of the addon knows: your recipes and when you usually play. Keep them to yourself if you like; change it any time in Options > Sharing." }
    list[#list + 1] = { key = "profile", icon = "Interface\\Icons\\INV_Misc_Note_01", title = "Your Profile",
        text = "A few basics guildmates see on your profile. All optional; you can edit them later from your profile's Edit button." }
    if ns.DB:IsGuildMaster() then
        list[#list + 1] = { key = "perms", icon = "Interface\\Icons\\INV_Crown_01", title = "Permissions (Guild Master)",
            text = "Choose which ranks may do each of these. \"Officers\" means the ranks the game marks Officer (Guild Control). You can change this any time in Options > Officers." }
    end
    list[#list + 1] = { key = "done", icon = D.LOGO, full = true, title = "You're All Set",
        text = ("Open the window any time with " .. ns.GOLD .. "/ngm|r or the minimap button.\n\n")
            .. ("Options has everything from this tour, plus an " .. ns.GOLD .. "About|r page with links to the Nootropic Discord and the addon's page.\n\n")
            .. ("Want this tour again? " .. ns.GOLD .. "/ngm welcome|r.") }
    return list
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function Check(parent, text, hint)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local label = cb.Text or cb.text
    if type(label) ~= "table" then
        label = cb:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    label:SetFontObject("NGMFontText")
    label:SetText(text)
    local h = parent:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    h:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    h:SetWidth(BODY_W - 34)
    h:SetJustifyH("LEFT")
    h:SetText(hint)
    cb.Hint = h
    return cb
end

local function Input(parent, label, maxLetters, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters)
    eb:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 6, -2)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb.Label = fs
    return eb
end

function WL:Build()
    local f = CreateFrame("Frame", "NootropicGMWelcome", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    W.SetTitle(f, "Nootropic Guild Manager")
    -- closing it any way counts as done (it can always be reopened)
    f:SetScript("OnHide", function() WL:SaveProfile(); ns.DB:Settings().welcomeDone = true end)
    self.frame = f

    TAB_ICONS = ns.UI.DEFAULT_TAB_ICONS

    -- a gold-edged picture frame for each page's icon
    local pic = CreateFrame("Frame", nil, f, "BackdropTemplate")
    pic:SetSize(76, 76)
    pic:SetPoint("TOPLEFT", 22, -44)
    pic:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    ns.Theme:Fill(pic, ns.Theme.C.bg1)
    ns.Theme:EdgeColor(pic, ns.Theme.C.yellow)
    self.icon = pic:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("TOPLEFT", 6, -6)
    self.icon:SetPoint("BOTTOMRIGHT", -6, 6)
    self.pic = pic

    self.title = f:CreateFontString(nil, "OVERLAY", "NGMFontTitle")
    self.title:SetPoint("TOPLEFT", pic, "TOPRIGHT", 18, -4)
    self.title:SetWidth(BODY_W)
    self.title:SetJustifyH("LEFT")

    self.text = f:CreateFontString(nil, "OVERLAY", "NGMFontText")
    self.text:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -10)
    self.text:SetWidth(BODY_W)
    self.text:SetJustifyH("LEFT")
    self.text:SetJustifyV("TOP")
    self.text:SetSpacing(3)

    -- page-specific controls live in their own frames below the text
    self.extras = {}
    self:BuildSharing(f)
    self:BuildProfile(f)
    self:BuildPerms(f)

    -- footer
    self.back = W.Button(f, "Back", 90, 24, "alt")
    self.back:SetPoint("BOTTOMLEFT", 16, 14)
    self.back:SetScript("OnClick", function() WL:Go(WL.index - 1) end)
    self.next = W.Button(f, "Next", 110, 24)
    self.next:SetPoint("BOTTOMRIGHT", -16, 14)
    self.next:SetScript("OnClick", function()
        if WL.index >= #WL.pages then f:Hide() else WL:Go(WL.index + 1) end
    end)
    self.skip = CreateFrame("Button", nil, f)
    self.skip:SetSize(90, 20)
    self.skip:SetPoint("RIGHT", self.next, "LEFT", -12, 0)
    self.skip.Text = self.skip:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.skip.Text:SetPoint("RIGHT")
    self.skip.Text:SetText("Skip the tour")
    self.skip:SetScript("OnClick", function() f:Hide() end)
    self.skip:SetScript("OnEnter", function(b) b.Text:SetTextColor(1, 1, 1) end)
    self.skip:SetScript("OnLeave", function(b) b.Text:SetTextColor(0.6, 0.6, 0.6) end)

    self.dots = {}
    self.dotBar = CreateFrame("Frame", nil, f)
    self.dotBar:SetSize(10, 10)
    self.dotBar:SetPoint("BOTTOM", 0, 22)

    ns:On("GUILD_SETTINGS_CHANGED", function() if f:IsShown() then WL:RefreshPerms() end end)
end

-- Sharing page: the same switches as Options > Sharing
function WL:BuildSharing(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(BODY_W, 220)
    self.extras.sharing = p
    local rows = {
        { "recipes", "Share my recipes", "So guildmates can find you in Who Can Craft?. Shared when you open a profession window." },
        { "learn", "Learn when I usually play", "Shares a summary of the hours you usually play (this character), for Play Together and your profile." },
    }
    p.checks = {}
    local y = 0
    for _, r in ipairs(rows) do
        local cb = Check(p, r[2], r[3])
        cb:SetPoint("TOPLEFT", -4, y)
        cb:SetScript("OnClick", function(b)
            local on = b:GetChecked() and true or false
            if r[1] == "learn" then ns.Profile:SetLearn(on) else ns.Sharing:Set(r[1], on) end
        end)
        p.checks[r[1]] = cb
        y = y - 44
    end
end

-- Profile page: Discord, roles
function WL:BuildProfile(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(BODY_W, 220)
    self.extras.profile = p
    p.discord = Input(p, "Discord name", ns.Profile.DISCORD_MAX, 220)
    p.discord.Label:SetPoint("TOPLEFT", 0, 0)
    local rl = p:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    rl:SetPoint("TOPLEFT", 0, -52)
    rl:SetText("Roles you play on this character")
    p.roles = {}
    local x = 0
    for _, r in ipairs(D.ROLES) do
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", x - 4, -68)
        local label = cb.Text or cb.text
        if type(label) ~= "table" then
            label = cb:CreateFontString(nil, "OVERLAY", "NGMFontText")
            label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        end
        label:SetFontObject("NGMFontText")
        label:SetText(("|T%s:16|t %s"):format(r.icon, r.label))
        cb.key = r.key
        cb:SetScript("OnClick", function() WL:SaveRoles() end)
        p.roles[#p.roles + 1] = cb
        x = x + 130
    end
    p.locked = p:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    p.locked:SetPoint("TOPLEFT", 0, -104)
    p.locked:SetWidth(BODY_W)
    p.locked:SetJustifyH("LEFT")
end

-- Guild Master page: one row per permission
function WL:BuildPerms(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(BODY_W, 220)
    self.extras.perms = p
    p.rows = {}
    local y = 0
    for _, perm in ipairs(ns.DB.PERMS) do
        local label = p:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("TOPLEFT", 0, y - 4)
        label:SetWidth(200)
        label:SetJustifyH("LEFT")
        label:SetText(perm.label)
        local btn = W.Button(p, "", 210, 22)
        btn:SetPoint("TOPLEFT", 210, y)
        btn:SetScript("OnClick", function(b) ns.Options:PermMenu(b, perm.key) end)
        W.Tooltip(btn, perm.label, perm.hint)
        p.rows[#p.rows + 1] = { key = perm.key, btn = btn }
        y = y - 32
    end
end

function WL:RefreshPerms()
    for _, row in ipairs(self.extras.perms.rows) do row.btn:SetText(ns.DB:PermText(row.key)) end
end

function WL:RefreshSharing()
    local c = self.extras.sharing.checks
    c.recipes:SetChecked(ns.Sharing:Get("recipes"))
    c.learn:SetChecked(ns.Profile:LearnEnabled())
end

function WL:RefreshProfile()
    local p = self.extras.profile
    local me = ns.PlayerFullName()
    local canContact = ns.DB:Guild() and ns.Profile:CanEditContact(me)
    local canRoles = ns.DB:Guild() and ns.Sync:CanWrite("RL:" .. me)
    p.discord:SetText(ns.Profile:Contact(me) or "")
    p.discord:SetEnabled(canContact and true or false)
    local m = ns.DB:GetMember(me)
    local have = {}
    for k in ((m and m.roles) or ""):gmatch("[^,]+") do have[k] = true end
    for _, cb in ipairs(p.roles) do
        cb:SetChecked(have[cb.key] or false)
        cb:SetEnabled(canRoles and true or false)
    end
    if not IsInGuild() then
        p.locked:SetText("Join a guild to fill these in: they're shared with your guild.")
    elseif not (canContact and canRoles) then
        p.locked:SetText("Your rank can't edit its own profile (the Guild Master's choice). An officer can fill these in for you.")
    else
        p.locked:SetText(GRAY .. "Saved when you move on. Guildmates see these on your profile.|r")
    end
end

function WL:SaveProfile()
    local p = self.extras and self.extras.profile
    if not (p and IsInGuild() and ns.DB:Guild()) then return end
    local me = ns.PlayerFullName()
    if ns.Profile:CanEditContact(me) then
        local d = ns.Profile:Contact(me)
        local nd = ns.Trim(p.discord:GetText() or "")
        if nd ~= (d or "") then ns.Profile:SetContact(me, nd) end
    end
end

function WL:SaveRoles()
    local me = ns.PlayerFullName()
    if not (ns.DB:Guild() and ns.Sync:CanWrite("RL:" .. me)) then return end
    local set = {}
    for _, cb in ipairs(self.extras.profile.roles) do
        if cb:GetChecked() then set[cb.key] = true end
    end
    ns.DB:SetRoles(me, set)
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------
function WL:Go(i)
    if self.extras.profile:IsShown() then self:SaveProfile() end
    i = math.max(1, math.min(#self.pages, i))
    self.index = i
    local page = self.pages[i]
    self.icon:SetTexture(page.icon or D.LOGO)
    if page.full then self.icon:SetTexCoord(0, 1, 0, 1) else self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    self.title:SetText(page.title)
    self.text:SetText(page.text)
    for key, frame in pairs(self.extras) do frame:SetShown(key == page.key) end
    local extra = self.extras[page.key]
    if extra then
        extra:ClearAllPoints()
        extra:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", 0, -16)
        if page.key == "sharing" then self:RefreshSharing()
        elseif page.key == "profile" then self:RefreshProfile()
        elseif page.key == "perms" then self:RefreshPerms() end
    end
    self.back:SetShown(i > 1)
    self.next:SetText(i == #self.pages and "Finish" or (i == 1 and "Start the Tour" or "Next"))
    self.skip:SetShown(i < #self.pages)
    -- page dots
    for n = 1, #self.pages do
        local dot = self.dots[n]
        if not dot then
            dot = self.dotBar:CreateTexture(nil, "ARTWORK")
            dot:SetSize(8, 8)
            dot:SetTexture("Interface\\Common\\Indicator-Gray")
            self.dots[n] = dot
        end
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self.dotBar, "CENTER", (n - (#self.pages + 1) / 2) * 14, 0)
        dot:SetTexture(n == i and "Interface\\Common\\Indicator-Yellow" or "Interface\\Common\\Indicator-Gray")
        dot:Show()
    end
    for n = #self.pages + 1, #self.dots do self.dots[n]:Hide() end
end

function WL:Open()
    if not self.frame then self:Build() end
    self.pages = Pages()
    self.frame:Show()
    self:Go(1)
end

-- First launch (and once for everyone updating to 2.5.0).
function WL:Init()
    if ns.DB:Settings().welcomeDone then return end
    C_Timer.After(8, function()
        if ns.DB:Settings().welcomeDone then return end
        if InCombatLockdown() then
            ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                if not ns.DB:Settings().welcomeDone and not (WL.frame and WL.frame:IsShown()) then WL:Open() end
            end)
            return
        end
        WL:Open()
    end)
end
