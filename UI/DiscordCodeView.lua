--[[
    Nootropic Guild Manager - /ngm discord: codes for NGM Peon
    Shows the Guild Master the code to paste on NGM Peon's dashboard (the
    update code: ranks and what changed in game) or into /ngm-guild setup in
    Discord (/ngm discord setup: the short setup code). Copying works like the invite prompt: the code is selected for
    you to press Ctrl+C; the addon never touches the clipboard or chat box.

    ns.DiscordCodeView:Open(mode)   -- mode: nil (changes), "all" or "setup"
]]
local _, ns = ...
local W = ns.Widgets
local V = {}
ns.DiscordCodeView = V

function V:Build()
    local f = CreateFrame("Frame", "NootropicGMDiscordCode", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(460, 262)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "NGM Peon Setup")
    tinsert(UISpecialFrames, "NootropicGMDiscordCode") -- Escape closes it
    self.frame = f

    local steps = f:CreateFontString(nil, "OVERLAY", "NGMFontText")
    steps:SetPoint("TOPLEFT", 20, -36)
    steps:SetPoint("TOPRIGHT", -20, -36)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    -- the steps depend on the code: set in Open
    self.steps = steps

    self.what = f:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.what:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -12)
    self.what:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    self.what:SetJustifyH("LEFT")

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(410, 22)
    box:SetPoint("BOTTOM", 0, 74)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0) -- an update code can run to thousands of characters
    if box.SetMaxBytes then box:SetMaxBytes(0) end
    box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(V.code or ""); eb:HighlightText() end end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnKeyDown", function(eb, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.05, function() eb:ClearFocus() end)
            V.hint:SetText(V.mode == "setup" and "|cff20ff20Copied.|r Paste it into /ngm-guild setup in Discord."
                or "|cff20ff20Copied.|r Paste it on ngmpeon.app, Sync tab, step 2.")
        end
    end)
    self.box = box

    self.hint = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.hint:SetPoint("BOTTOM", 0, 48)
    self.hint:SetWidth(420)

    local copy = W.Button(f, "Select Code", 130, 24)
    copy:SetPoint("BOTTOM", 0, 14)
    copy:SetScript("OnClick", function() V:Select() end)
    W.Tooltip(copy, "Copy the code", "Selects the code so you can copy it with Ctrl+C.")
    self.copy = copy
end

function V:Select()
    if not self.code then return end
    self.box:SetText(self.code)
    self.box:SetFocus()
    self.box:HighlightText()
    self.hint:SetText("Press |cffffffffCtrl+C|r to copy.")
end

function V:Open(mode)
    local code, why, everything, count, since = ns.DiscordCode:ForMyGuild(mode)
    if not code then
        ns:Print("|cffff2020" .. why .. "|r")
        return
    end
    if not self.frame then self:Build() end
    self.code, self.mode = code, mode
    local n = #ns.DB:GuildRanks()
    if mode == "setup" then
        W.SetTitle(self.frame, "NGM Peon Setup")
        self.steps:SetText((ns.GOLD .. "1.|r Invite NGM Peon to your guild's Discord (|cffffffffngmpeon.app|r).\n")
            .. (ns.GOLD .. "2.|r In Discord, run |cffffffff/ngm-guild setup|r and paste this code.\n")
            .. (ns.GOLD .. "3.|r Sign in with Battle.net when NGM Peon asks."))
        self.what:SetText(("The code holds your guild's name, region, %d rank names and which ranks are Officer and Invite Member."):format(n))
    else
        W.SetTitle(self.frame, "Update NGM Peon")
        self.steps:SetText((ns.GOLD .. "1.|r Copy this code.\n")
            .. (ns.GOLD .. "2.|r On |cffffffffngmpeon.app|r, open the |cffffffffSync|r tab: step 2.\n")
            .. (ns.GOLD .. "3.|r Paste it, then sign in with Battle.net."))
        local changes = ("%d main / alt and Tank / Healer / DPS record%s"):format(count or 0, count == 1 and "" or "s")
        if everything then
            self.what:SetText("Everything: your ranks, When we play, and " .. changes .. ".")
        else
            self.what:SetText(("Holds %s changed in game since %s (NGM Peon skips any it already has), plus your ranks and When we play. "
                .. "|cffffffff/ngm discord all|r sends everything."):format(changes, date("%b %d", since or 0)))
        end
    end
    self.box:SetText(code)
    self.box:SetCursorPosition(0)
    self.hint:SetText("")
    self.frame:Show()
    self:Select()
end
