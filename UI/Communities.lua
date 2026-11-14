--[[
    Nootropic Guild Manager - Guild & Communities shortcut
    Adds a side tab with the addon icon to the game's Guild & Communities
    window, placed and drawn like Blizzard's own side tabs (32x32, frame
    level 510, the spellbook's tab art). No pushed
    art: the click opens our window, and the button can miss its mouse-up,
    which left Blizzard's pushed art stuck on. The older GuildFrame gets one
    too if this client has it. Each window gets its own tab, so one loading
    first never blocks the other.
]]
local _, ns = ...
local CM = {}
ns.Communities = CM

-- Blizzard's side tabs: ours goes under the lowest one showing. They aren't
-- a fixed set (Chat, Roster, Guild Info, Guild Benefits, Preferred Play
-- Settings... which show changes with the view), so they're found by where
-- they are: shown, tab-sized, down the window's right edge. Anchoring under
-- a named one left ours on top of another (their Preferred Play Settings
-- map, or their Guild Benefits tabard), sometimes drawn under it.
local TAB_LEVEL = 510
local GAP = 16 -- only when there's one tab of theirs to go by (else their own spacing)

local function SideTabs(host, mine)
    local list = {}
    local right = host:GetRight()
    if not right then return list end
    for _, c in ipairs({ host:GetChildren() }) do
        if c ~= mine and c:IsShown() and c.GetLeft then
            local left, w, h = c:GetLeft(), c:GetWidth(), c:GetHeight()
            if left and left >= right - 12 and left <= right + 40 and w >= 20 and w <= 64 and h >= 20 and h <= 64 then
                list[#list + 1] = c
            end
        end
    end
    return list
end

local hooked = setmetatable({}, { __mode = "k" })

-- Under the lowest of Blizzard's tabs that's showing, and above them all;
-- again whenever one of them shows or hides.
local function Place(b)
    local host = b:GetParent()
    local lowest, above, level = nil, nil, TAB_LEVEL
    for _, t in ipairs(SideTabs(host, b)) do
        local bottom = t:GetBottom()
        if bottom and (not lowest or bottom < lowest:GetBottom()) then
            above, lowest = lowest, t
        elseif bottom and (not above or bottom < above:GetBottom()) then
            above = t
        end
        level = math.max(level, (t:GetFrameLevel() or 0) + 2)
        if not hooked[t] then
            hooked[t] = true
            t:HookScript("OnShow", function() Place(b) end)
            t:HookScript("OnHide", function() Place(b) end)
        end
    end
    b:ClearAllPoints()
    if lowest then
        -- the same size and spacing as theirs: the gap between their two lowest
        local w, h = lowest:GetWidth(), lowest:GetHeight()
        if w and h and w > 0 and h > 0 then b:SetSize(w, h) end
        local gap = GAP
        if above and above:GetBottom() and lowest:GetTop() then
            local g = above:GetBottom() - lowest:GetTop()
            if g >= 0 and g <= 40 then gap = g end
        end
        b:SetPoint("TOPLEFT", lowest, "BOTTOMLEFT", 0, -gap)
    else
        b:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -36)
    end
    b:SetFrameLevel(math.max(level, host:GetFrameLevel() + 10))
end

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

    Place(b)
    -- again whenever the window opens (and once laid out, a moment later)
    host:HookScript("OnShow", function()
        Place(b)
        if C_Timer then C_Timer.After(0, function() Place(b) end) end
    end)

    -- Blizzard's own side tab art (as their tabs above it)
    local bg = b:CreateTexture(nil, "BORDER")
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)

    b.Icon = ns.Brand:Attach(b, 30, { "CENTER", b, "CENTER", 0, 0 }, { round = false, crop = 0.1 })

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- each time the window opens: the icon fresh (the tabard can load late)
    b:SetScript("OnShow", function(self) self.Icon:Apply(); Place(self) end)
    b:SetScript("OnClick", function() ns.UI:Show() end)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.UI:Title())
        GameTooltip:AddLine("Search the guild, recruit and see the audit.", 1, 1, 1, true)
        GameTooltip:AddLine("You can hide this tab in the addon's options.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
        local relName = rel and rel.GetName and rel:GetName() or (rel and tostring(rel)) or "?"
        ns:Print(("  tab on %s: shown=%s visible=%s level=%d, under %s"):format(name, tostring(b:IsShown()), tostring(b:IsVisible()), b:GetFrameLevel() or 0, relName))
        -- Blizzard's tabs it found, top to bottom
        for _, t in ipairs(SideTabs(b:GetParent(), b)) do
            ns:Print(("    side tab: %s, bottom %s"):format(t:GetName() or tostring(t), tostring(math.floor(t:GetBottom() or 0))))
        end
        -- what the button draws: each picture, shown or not, and its file
        local i = b.Icon
        if i then
            for _, key in ipairs({ "Base", "Cloth", "Band", "Top" }) do
                local t = i[key]
                if t then ns:Print(("    %s: shown=%s file=%s"):format(key, tostring(t:IsShown()), tostring(t:GetTexture()))) end
            end
        end
        -- anything of the game's drawn at the same spot, above it
        if b.GetCenter and b:GetParent() then
            local bx, by = b:GetCenter()
            for _, c in ipairs({ b:GetParent():GetChildren() }) do
                if c ~= b and c:IsVisible() and c.GetCenter then
                    local cx, cy = c:GetCenter()
                    if cx and bx and math.abs(cx - bx) < 16 and math.abs(cy - by) < 16 then
                        ns:Print(("    also here: %s level=%d"):format(c:GetName() or tostring(c), c:GetFrameLevel() or 0))
                    end
                end
            end
        end
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
