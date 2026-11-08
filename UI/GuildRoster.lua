--[[
    Nootropic Guild Manager - the game's Guild & Communities roster
    Adds this addon's data to Blizzard's own guild roster instead of
    replacing it:

      Rows      a few tag icons and an "alt" marker after each name
      Tooltip   tags, main / alts, Discord, usually online, professions
      Menu      right-click a member: Profile, Tags, Main / Alt
      Alt+click a member opens their profile docked beside the window

    Only additive, taint-safe hooks are used: our own child frames on the
    rows, HookScript on tooltips, ScrollUtil's row callback, and the
    official Menu.ModifyMenu. Blizzard's frames, sorting and protected
    actions (invite, promote, remove) are left untouched.
    Off switch: Options > "Show tags and alts on the Guild roster".
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local GR = {}
ns.GuildRoster = GR

local ICON = 12
local MAX_TAG_ICONS = 3
local decorated = setmetatable({}, { __mode = "k" }) -- rows we've added to

function GR:Enabled()
    return ns.DB:Settings().blizzRoster ~= false
end

function GR:SetEnabled(on)
    ns.DB:Settings().blizzRoster = on and true or false
    self:RefreshRows()
    ns:Fire("SETTINGS_CHANGED")
end

------------------------------------------------------------------------
-- Which member a Blizzard row (or menu) is about
------------------------------------------------------------------------
local function IsGuildView()
    local cf = CommunitiesFrame
    if not (cf and C_Club and C_Club.GetGuildClubId) then return false end
    local guildId = C_Club.GetGuildClubId()
    local sel = cf.GetSelectedClubId and cf:GetSelectedClubId()
    return guildId ~= nil and sel == guildId
end

-- Our roster entry for a club member info table ({ guid, name, ... }).
local function EntryFor(info)
    if type(info) ~= "table" then return nil end
    local R = ns.Roster
    if info.guid and R.byGuid and R.byGuid[info.guid] then return R.byGuid[info.guid] end
    local name = info.name or info.fullName
    if name and name ~= "" then return R.byName[ns.NormalizeName(name)] end
end

local function RowEntry(row)
    local info = row.GetMemberInfo and row:GetMemberInfo()
    return EntryFor(info)
end

local function EntryForName(name)
    if not name or name == "" then return nil end
    return ns.Roster.byName[ns.NormalizeName(name)]
end

------------------------------------------------------------------------
-- Opening our profile beside the Guild & Communities window
------------------------------------------------------------------------
function GR:OpenProfile(e)
    if not e then return end
    local host = CommunitiesFrame
    if not (host and host:IsShown()) then host = nil end
    ns.DetailPanel:Show(e.full, host)
end

------------------------------------------------------------------------
-- Rows: tag icons and an alt marker after the name
------------------------------------------------------------------------
local function Badge(row)
    local b = row.NGMBadge
    if b then return b end
    b = CreateFrame("Frame", nil, row)
    b:SetSize(ICON * (MAX_TAG_ICONS + 1) + 8, ICON)
    b:SetFrameLevel(row:GetFrameLevel() + 3)
    b:EnableMouse(false)
    b.icons = {}
    for i = 1, MAX_TAG_ICONS do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(ICON, ICON)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icons[i] = t
    end
    b.Alt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.Alt:SetText("alt")
    row.NGMBadge = b
    return b
end

-- The name text on a Blizzard roster row, if this client has one where we expect it.
local function NameText(row)
    local nf = row.NameFrame
    return (nf and nf.Name) or row.Name
end

function GR:DecorateRow(row)
    local e = self:Enabled() and IsGuildView() and RowEntry(row)
    local b = row.NGMBadge
    if not e then
        if b then b:Hide() end
        return
    end
    b = Badge(row)
    local x = 0
    for i = 1, MAX_TAG_ICONS do
        local tag, t = e.tagList and e.tagList[i], b.icons[i]
        if tag then
            W.SetIcon(t, D:TagIcon(tag))
            t:ClearAllPoints()
            t:SetPoint("LEFT", x, 0)
            t:Show()
            x = x + ICON + 1
        else
            t:Hide()
        end
    end
    b.Alt:ClearAllPoints()
    b.Alt:SetPoint("LEFT", x + (x > 0 and 3 or 0), 0)
    b.Alt:SetShown(e.isAlt and true or false)
    if e.isAlt then x = x + 3 + math.ceil(b.Alt:GetStringWidth()) end
    b:SetWidth(math.max(1, x))
    b:ClearAllPoints()
    local name = NameText(row)
    if name then
        -- right after the visible name, never past the name column
        local w = math.min(math.ceil(name:GetStringWidth() or 0), math.max(0, (name:GetWidth() or 0) - x - 4))
        b:SetPoint("LEFT", name, "LEFT", w + 4, 0)
    else
        b:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    b:SetShown(x > 0)
end

-- Tooltip lines: added after Blizzard's own (HookScript runs after theirs).
function GR:AddTooltip(e)
    if not (e and GameTooltip:IsShown()) then return end
    local GOLD = { 1, 0.82, 0 }
    local function Pair(left, right)
        GameTooltip:AddDoubleLine(left, right, GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Nootropic Guild Manager", 0.6, 0.6, 0.6)
    if e.isAlt then
        Pair("Alt of", e.mainShort)
    elseif e.alts and #e.alts > 0 then
        local names = {}
        for i, full in ipairs(e.alts) do names[i] = ns.ShortName(full) end
        Pair("Alts", table.concat(names, ", "))
    end
    if e.spec then Pair("Specialization", e.spec) end
    if e.roleList and #e.roleList > 0 then Pair("Role", table.concat(e.roleList, ", ")) end
    if e.profs and #e.profs > 0 then
        local parts = {}
        for i, p in ipairs(e.profs) do
            parts[i] = p.name .. ((p.rank and p.rank > 0) and (" " .. p.rank) or "")
        end
        Pair("Professions", table.concat(parts, ", "))
    end
    if e.discord then Pair("Discord", e.discord) end
    local PF = ns.Profile
    local hours = PF:Hours(e.full)
    local summary = hours and PF.Summary(hours)
    if summary then GameTooltip:AddLine(("Usually online: %s (%s)"):format(summary, PF.ClockLabel()), 0.7, 0.7, 0.7, true) end
    if e.tagList and #e.tagList > 0 then
        local names = {}
        for i, tag in ipairs(e.tagList) do names[i] = D:TagLabel(tag, 12) end
        GameTooltip:AddLine(table.concat(names, "  "), 1, 1, 1, true)
    end
    GameTooltip:AddLine("Alt+click or right-click for the profile.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function HookRow(row)
    if decorated[row] then return end
    decorated[row] = true
    row:HookScript("OnEnter", function(self)
        if not (GR:Enabled() and IsGuildView()) then return end
        if GameTooltip:GetOwner() ~= self then return end
        GR:AddTooltip(RowEntry(self))
    end)
    row:HookScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and GR:Enabled() and IsGuildView() then
            GR:OpenProfile(RowEntry(self))
        end
    end)
end

local function ScrollBox()
    local list = CommunitiesFrame and CommunitiesFrame.MemberList
    return list and list.ScrollBox
end

function GR:RefreshRows()
    local sb = ScrollBox()
    if not (sb and sb.ForEachFrame) then return end
    sb:ForEachFrame(function(row) GR:DecorateRow(row) end)
end

------------------------------------------------------------------------
-- Right-click menu (Menu.ModifyMenu, the official way to add entries)
------------------------------------------------------------------------
local MENU_TAGS = {
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_GUILD",
}

local function MenuEntry(owner, contextData)
    local cd = contextData or {}
    local e = EntryFor(cd.clubMemberInfo) or EntryForName(cd.name)
    if not e and owner and owner.GetMemberInfo then e = EntryFor(owner:GetMemberInfo()) end
    return e
end

function GR:AddMenu(owner, root, contextData)
    if not self:Enabled() then return end
    local e = MenuEntry(owner, contextData)
    if not e then return end
    local full = e.full
    root:CreateDivider()
    root:CreateTitle("Nootropic Guild Manager")
    root:CreateButton("Profile", function() GR:OpenProfile(ns.Roster.byName[full]) end)
    if ns.DB:CanEditTags(full) and #ns.DB:GetTags() > 0 then
        local sub = root:CreateButton("Tags")
        for _, tag in ipairs(ns.DB:GetTags()) do
            local id = tag.id
            sub:CreateCheckbox(D:TagLabel(tag, 14),
                function() local m = ns.DB:GetMember(full); return (m and m.tags and m.tags[id]) and true or false end,
                function() ns.DB:SetTag(full, id) end)
        end
    end
    if ns.DB:CanEditLinks() then
        local sub = root:CreateButton("Main / Alt")
        local cur = ns.Roster.byName[full]
        if cur and cur.isAlt then
            sub:CreateButton("Change main...", function() GR:OpenProfile(cur); ns.DetailPanel:PickMainFor(full) end)
            sub:CreateButton("Make " .. cur.short .. " the main", function() ns.DB:MakeMain(full) end)
            sub:CreateButton("Unlink from " .. (cur.mainShort or "main"), function() ns.DB:ClearMain(full) end)
        else
            sub:CreateButton("Mark as alt of...", function() GR:OpenProfile(cur); ns.DetailPanel:PickMainFor(full) end)
            sub:CreateButton("Add an alt...", function() GR:OpenProfile(cur); ns.DetailPanel:PickAltFor(full) end)
        end
    end
end

------------------------------------------------------------------------
-- Hooking the window when it loads
------------------------------------------------------------------------
function GR:Attach()
    if self.attached then return end
    local sb = ScrollBox()
    if not sb then return end
    self.attached = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(sb, function(_, row)
            HookRow(row)
            GR:DecorateRow(row)
        end, GR, true)
    elseif sb.ForEachFrame then
        -- older ScrollBox: decorate whatever is shown whenever the list updates
        sb:ForEachFrame(function(row) HookRow(row) end)
    end
    local list = CommunitiesFrame.MemberList
    if list and list.RefreshListDisplay then
        hooksecurefunc(list, "RefreshListDisplay", function()
            if sb.ForEachFrame then sb:ForEachFrame(function(row) HookRow(row) end) end
            GR:RefreshRows()
        end)
    end
end

function GR:Diagnose()
    local sb = ScrollBox()
    local rows, named = 0, 0
    if sb and sb.ForEachFrame then
        sb:ForEachFrame(function(row)
            rows = rows + 1
            if RowEntry(row) then named = named + 1 end
        end)
    end
    ns:Print(("Guild roster: hooked=%s, guild view=%s, rows=%d, matched=%d, menus=%s, ScrollUtil=%s"):format(
        tostring(self.attached or false), tostring(IsGuildView()), rows, named,
        tostring(self.menus or false), tostring(ScrollUtil ~= nil)))
end

function GR:Init()
    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENU_TAGS) do
            pcall(Menu.ModifyMenu, tag, function(owner, root, contextData) GR:AddMenu(owner, root, contextData) end)
        end
        self.menus = true
    end
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Communities" then GR:Attach() end
    end)
    if hooksecurefunc and _G.ToggleCommunitiesFrame then
        hooksecurefunc("ToggleCommunitiesFrame", function() GR:Attach() end)
    end
    self:Attach()
    local function refresh() ns.Debounce("guildrosterrows", 0.1, function() GR:RefreshRows() end) end
    ns:On("ROSTER_UPDATED", refresh)
    ns:On("TAGS_CHANGED", refresh)
    ns:On("MEMBER_CHANGED", refresh)
end
