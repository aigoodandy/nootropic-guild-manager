--[[
    Nootropic Guild Manager - Invite prompt
    WoW: Forever blocks guild invites that come from an addon in any way:
    calling C_GuildInfo.Invite (2.1.5), /ginvite from a secure macro button
    (2.1.6/2.1.7), and /ginvite put in the chat box by the addon (2.1.8; the
    addon opening the chat box taints it). Only /ginvite you type yourself
    works. So the prompt shows the command, selected, for you to copy: Ctrl+C,
    then Enter (you open chat), Ctrl+V, Enter. The addon never touches the
    chat box. The game's "You have invited ..." message then marks them
    invited and shows the next one.

    Shown when someone replies with an invite keyword, and from "Invite to
    Guild" on the Recruitment list. Several waiting invites queue up.

    ns.InvitePrompt:Show(full, reply)
]]
local _, ns = ...
local W = ns.Widgets
local IP = {}
ns.InvitePrompt = IP

IP.queue = {} -- { { full, reply }, ... } waiting behind the one shown

function IP:Build()
    local f = CreateFrame("Frame", "NootropicGMInvitePrompt", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(380, 214)
    f:SetPoint("TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    -- not a top-level frame: raising itself on click would lift the Invite
    -- button above its secure overlay
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "Guild Invite")
    self.frame = f

    local text = f:CreateFontString(nil, "OVERLAY", "NGMFontText")
    text:SetPoint("TOPLEFT", 18, -34)
    text:SetPoint("TOPRIGHT", -18, -34)
    text:SetJustifyH("CENTER")
    text:SetSpacing(3)
    self.text = text

    self.more = f:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.more:SetPoint("TOPRIGHT", -30, -6)

    -- the game confirms a sent invite in a system message
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, _, msg) IP:OnSystemMessage(msg) end)

    -- the command to copy: read-only, selected when you click Copy
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(300, 22)
    box:SetPoint("BOTTOM", 0, 74)
    box:SetAutoFocus(false)
    box:SetJustifyH("CENTER")
    box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(IP.command or ""); eb:HighlightText() end end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnKeyDown", function(eb, key)
        if key == "C" and IsControlKeyDown() then
            -- let the copy happen, then step out of the way so Enter opens chat
            C_Timer.After(0.05, function() eb:ClearFocus() end)
            IP.copied = IP.full
            IP:Render()
        end
    end)
    self.box = box

    local invite = W.Button(f, "Copy Invite", 130, 24)
    invite:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
    invite:SetScript("OnClick", function() IP:SelectCommand() end)
    W.Tooltip(invite, "Copy the invite", "Selects the /ginvite command so you can copy it (Ctrl+C), then press Enter, paste it (Ctrl+V) and press Enter. WoW: Forever only accepts guild invites you type yourself.")
    self.inviteButton = invite

    self.hint = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.hint:SetPoint("BOTTOM", 0, 48)
    self.hint:SetWidth(350)

    local later = W.Button(f, "Not now", 110, 24, "alt")
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
    later:SetScript("OnClick", function() IP:Next() end)

    -- the frame's own close button skips everything waiting
    if f.CloseButton then f.CloseButton:HookScript("OnClick", function() wipe(IP.queue); IP.full = nil end) end
end

-- Selects the command in the box so Ctrl+C copies it.
function IP:SelectCommand()
    local full = self.full
    if not full then return end
    local ok, err = ns.Recruit:CanInviteNow(full)
    if not ok then
        if err then ns:Print("|cffff2020" .. err .. "|r") end
        return
    end
    self.box:SetText(self.command or "")
    self.box:SetFocus()
    self.box:HighlightText()
end

-- "You have invited Audrey Pichhale to join your guild."
local INVITED = (ERR_GUILD_INVITE_S or "You have invited %s to join your guild.")
    :gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
INVITED = "^" .. INVITED .. "$"

function IP:OnSystemMessage(msg)
    local who = msg and msg:match(INVITED)
    if not who then return end
    local function same(full) return full and ns.ChatName(full):lower() == who:lower() end
    local hit
    if same(self.full) then
        hit = self.full
    else
        for i, q in ipairs(self.queue) do
            if same(q.full) then hit = q.full; table.remove(self.queue, i); break end
        end
    end
    if not hit then return end
    ns.Recruit:MarkInvited(hit)
    if hit == self.full then self:Next() else self:Render() end
end

function IP:Render()
    local name = ns.ShortName(self.full)
    if self.reply and self.reply ~= "" then
        self.text:SetText(((ns.GOLD .. "%s|r replied:\n\"%s\"\n\nInvite them to the guild?")):format(name, self.reply))
    else
        self.text:SetText((("Invite " .. ns.GOLD .. "%s|r to the guild?")):format(name))
    end
    local n = #self.queue
    self.more:SetText(n > 0 and (n == 1 and "1 more waiting" or (n .. " more waiting")) or "")
    self.command = "/ginvite " .. ns.ChatName(self.full)
    if self.box and not self.box:HasFocus() then self.box:SetText(self.command) end
    local copied = self.copied and self.copied == self.full
    self.hint:SetText(copied
        and "Copied. Now press |cffffffffEnter|r, |cffffffffCtrl+V|r, |cffffffffEnter|r."
        or "Click Copy Invite, press |cffffffffCtrl+C|r, then |cffffffffEnter|r, |cffffffffCtrl+V|r, |cffffffffEnter|r.")
end

function IP:Show(full, reply)
    if not full then return end
    if not self.frame then self:Build() end
    if self.full == full then
        self.reply = reply or self.reply
        self:Render()
        return
    end
    for _, q in ipairs(self.queue) do
        if q.full == full then q.reply = reply or q.reply; self:Render(); return end
    end
    if self.full and self.frame:IsShown() then
        table.insert(self.queue, { full = full, reply = reply })
        self:Render()
        return
    end
    self.full, self.reply = full, reply
    self:Render()
    self.frame:Show()
    ns.PlaySound("TELL_MESSAGE")
end

-- Shows the next waiting invite, or closes.
function IP:Next()
    -- let go of the box first, so the next person's command replaces the
    -- old one (a focused box keeps its text)
    self.copied = nil
    if self.box then self.box:ClearFocus() end
    local q = table.remove(self.queue, 1)
    if q then
        self.full, self.reply = q.full, q.reply
        self:Render()
    else
        self.full, self.reply = nil, nil
        if self.frame then self.frame:Hide() end
    end
end

