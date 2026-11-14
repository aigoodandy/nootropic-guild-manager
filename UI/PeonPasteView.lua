--[[
    Nootropic Guild Manager - /ngm peon: bring in a code from NGM Peon
    The dashboard's Sync tab (step 3) gives a code with what was
    set there: mains and alts, Tank / Healer / DPS, fixes for wrong links. It
    also says what NGM Peon already has, so the next /ngm discord only carries
    new changes. Pasted here, its records are taken under the addon's usual
    rules and shared with the guild (Services/DiscordCode.lua, ApplyPeon).

    ns.PeonPasteView:Open()
]]
local _, ns = ...
local W = ns.Widgets
local V = {}
ns.PeonPasteView = V

function V:Build()
    local f = CreateFrame("Frame", "NootropicGMPeonPaste", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(460, 340)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "From NGM Peon")
    tinsert(UISpecialFrames, "NootropicGMPeonPaste") -- Escape closes it
    self.frame = f

    local steps = f:CreateFontString(nil, "OVERLAY", "NGMFontText")
    steps:SetPoint("TOPLEFT", 20, -36)
    steps:SetPoint("TOPRIGHT", -20, -36)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    steps:SetText((ns.GOLD .. "1.|r On |cffffffffngmpeon.app|r, open the |cffffffffSync|r tab: step 3.\n")
        .. (ns.GOLD .. "2.|r Copy it and paste it below (Ctrl+V).\n")
        .. (ns.GOLD .. "3.|r Press Bring In."))

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(410, 22)
    box:SetPoint("TOP", steps, "BOTTOM", 0, -16)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0) -- a code can run to thousands of characters
    if box.SetMaxBytes then box:SetMaxBytes(0) end
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() V:BringIn() end)
    self.box = box

    self.result = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.result:SetPoint("TOP", box, "BOTTOM", 0, -12)
    self.result:SetWidth(420)
    self.result:SetJustifyH("CENTER")

    local go = W.Button(f, "Bring In", 130, 24)
    go:SetPoint("BOTTOM", 0, 14)
    go:SetScript("OnClick", function() V:BringIn() end)
    W.Tooltip(go, "Bring in the code", "Takes what NGM Peon has into your game and shares it with the guild.")
end

function V:BringIn()
    local got, why = ns.DiscordCode:ApplyPeon(self.box:GetText())
    if not got then
        self.result:SetText("|cff" .. ns.Theme.HEX.red .. why .. "|r")
        return
    end
    -- counts, not names: a first code can carry the whole guild
    local function n(k, one, many) return ("%d %s"):format(k, k == 1 and one or many) end
    local lines = { "|cff" .. ns.Theme.HEX.green .. "Done.|r" }
    lines[#lines + 1] = got.players > 0 and ("Mains and alts: " .. n(got.players, "player", "players") .. " changed") or "Mains and alts: nothing new"
    lines[#lines + 1] = got.characters > 0 and ("Tank / Healer / DPS: " .. n(got.characters, "character", "characters") .. " changed") or "Tank / Healer / DPS: nothing new"
    lines[#lines + 1] = got.names > 0 and ("Discord names: " .. n(got.names, "member", "members") .. " added or changed") or "Discord names: nothing new"
    if got.months > 0 then lines[#lines + 1] = "Hall of Fame champions: " .. n(got.months, "month", "months") .. " crowned by NGM Peon" end
    if got.had > 0 then lines[#lines + 1] = "|cff" .. ns.Theme.HEX.dim .. "Already had: " .. got.had .. " (no change needed)|r" end
    if got.refused > 0 then
        lines[#lines + 1] = ((ns.ORANGE .. "%d not taken|r: your rank can only bring in your own. An officer can bring in the rest.")):format(got.refused)
    end
    lines[#lines + 1] = "Shared with the guild."
    -- Upcoming Events: what changed, then how many there are
    local changes = {}
    if (got.eventsNew or 0) > 0 then changes[#changes + 1] = n(got.eventsNew, "new event", "new events") end
    if (got.eventsRemoved or 0) > 0 then changes[#changes + 1] = n(got.eventsRemoved, "event removed", "events removed") end
    if #changes > 0 or (got.events or 0) > 0 then
        lines[#lines + 1] = "Upcoming Events: " .. (#changes > 0 and (table.concat(changes, ", ") .. "; ") or "")
            .. ns.GOLD .. n(got.events or 0, "upcoming", "upcoming") .. "|r (Upcoming Events tab)"
    end
    self.result:SetText(table.concat(lines, "\n"))
    local changed = got.players + got.characters + got.names + got.months
    -- the herald's moment: word from Discord
    local news = (got.eventsNew or 0) > 0 and (n(got.eventsNew, "new event", "new events") .. ". ") or ""
    ns.Theme:Toast("Word from Discord", (changed > 0 or news ~= "") and (news .. "Shared with the guild.") or "Nothing new from NGM Peon.")

    self.box:SetText("")
    self.box:ClearFocus()
end

function V:Open()
    if not self.frame then self:Build() end
    self.box:SetText("")
    self.result:SetText("")
    self.frame:Show()
    self.box:SetFocus()
end
