--[[
    Nootropic Guild Manager - Guild & Communities shortcut
    Adds a side tab with the addon icon to the game's Guild & Communities
    window, matching Blizzard's own side tabs (CommunitiesFrameTabTemplate:
    32x32, frame level 510, spellbook tab art, 30x30 icon). The older
    GuildFrame gets one too if this client has it. Each window gets its own
    tab, so one loading first never blocks the other.
]]
local _, ns = ...
local CM = {}
ns.Communities = CM

-- Blizzard's side tabs, top to bottom; ours goes under the last one present.
local SIDE_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
local TAB_LEVEL = 510

CM.buttons = {} -- [hostName] = button

local function Hosts()
    local list = {}
    if CommunitiesFrame then list[#list + 1] = { name = "CommunitiesFrame", frame = CommunitiesFrame } end
    if GuildFrame then list[#list + 1] = { name = "GuildFrame", frame = GuildFrame } end
    return list
end

function CM:IsEnabled()
    return ns.DB:Settings().communitiesButton ~= false
end

function CM:SetEnabled(on)
    ns.DB:Settings().communitiesButton = on and true or false
    self:Attach()
    for _, b in pairs(self.buttons) do b:SetShown(on) end
    ns:Fire("SETTINGS_CHANGED")
end

local function CreateTab(host)
    local b = CreateFrame("Button", nil, host)
    b:SetSize(32, 32)
    b:SetFrameLevel(math.max(TAB_LEVEL, host:GetFrameLevel() + 10))

    local anchor
    for _, key in ipairs(SIDE_TABS) do
        if host[key] then anchor = host[key] end
    end
    if anchor then
        b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    else
        b:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -36)
    end

    local bg = b:CreateTexture(nil, "BORDER")
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)

    b.Icon = ns.Brand:Attach(b, 30, { "CENTER", b, "CENTER", 0, 0 }, { round = false })

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetScript("OnClick", function() ns.UI:Show() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.UI:Title())
        GameTooltip:AddLine("Open the roster, recruitment, tags and audit.", 1, 1, 1, true)
        GameTooltip:AddLine("You can hide this tab in the addon's options.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function CM:Attach()
    for _, h in ipairs(Hosts()) do
        local b = self.buttons[h.name]
        if not b then
            b = CreateTab(h.frame)
            self.buttons[h.name] = b
        end
        b:SetShown(self:IsEnabled())
    end
end

-- /ngm diag: what the shortcut can see, for troubleshooting.
function CM:Diagnose()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
    ns:Print(("Guild & Communities: addon loaded=%s, CommunitiesFrame=%s, GuildFrame=%s, shortcut enabled=%s"):format(
        tostring(loaded), tostring(CommunitiesFrame ~= nil), tostring(GuildFrame ~= nil), tostring(self:IsEnabled())))
    for name, b in pairs(self.buttons) do
        local _, rel = b:GetPoint(1)
        ns:Print(("  tab on %s: shown=%s visible=%s level=%d"):format(name, tostring(b:IsShown()), tostring(b:IsVisible()), b:GetFrameLevel() or 0))
    end
    if next(self.buttons) == nil then ns:Print("  no tab yet - open the Guild & Communities window once, then run /ngm diag again.") end
end

function CM:Init()
    -- The Guild & Communities window loads on demand, so watch for it.
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" then CM:Attach() end
    end)
    -- Some clients create the window without a separate load event.
    if hooksecurefunc then
        for _, fn in ipairs({ "ToggleGuildFrame", "ToggleCommunitiesFrame" }) do
            if _G[fn] then hooksecurefunc(fn, function() CM:Attach() end) end
        end
    end
    self:Attach()
end
