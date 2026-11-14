--[[
    Nootropic Guild Manager - Core
    Namespace, internal events/callbacks, shared utilities and slash commands.
]]
local ADDON_NAME, ns = ...
_G.NootropicGuildManager = ns -- exposed for /dump debugging

ns.name = ADDON_NAME
ns.GOLD = "|cffffd100"   -- the accent (the guild theme changes these: UI/Theme.lua ApplyPalette)
ns.ORANGE = "|cffff8000"
ns.BLUE = "|cff71d5ff"
ns.GRAY = "|cff9d9d9d"

local function Meta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, field)
    end
end
ns.version = Meta("Version") or "dev"

------------------------------------------------------------------------
-- Tab names in text ("Open the Recruitment tab"). key: "roster",
-- "together", "overview", "recruit" or "audit".
------------------------------------------------------------------------
local TAB_NAMES = { roster = "Find", together = "Play Together", overview = "Overview", hof = "Hall of Fame", recruit = "Recruitment", audit = "Audit" }

function ns.TabName(key)
    return TAB_NAMES[key] or key
end

------------------------------------------------------------------------
-- Printing
------------------------------------------------------------------------
function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(ns.GOLD .. "Nootropic GM:|r " .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Internal callbacks (module <-> module messaging)
------------------------------------------------------------------------
local listeners = {}

function ns:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

------------------------------------------------------------------------
-- Game events
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Safe registration: unknown events (they differ between clients) are skipped.
function ns:RegisterEvent(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------
local pending = {}
-- Runs fn once, `delay` seconds after the most recent call with this key.
function ns.Debounce(key, delay, fn)
    local token = (pending[key] or 0) + 1
    pending[key] = token
    C_Timer.After(delay, function()
        if pending[key] == token then fn() end
    end)
end

-- "1.13-beta2" -> { 1, 13 }, "beta2"
local function ParseVersion(v)
    local main, tag = tostring(v or ""):match("^([^%-]*)%-?(.*)$")
    local parts = {}
    for n in main:gmatch("[^%.]+") do parts[#parts + 1] = tonumber(n:match("^%d+") or "") or 0 end
    return parts, tag
end

-- -1, 0 or 1 comparing versions like "1.9" and "1.10" part by part.
-- Anything that isn't a number counts as 0 ("dev" < "1.0"). A beta comes
-- before its release and after the one before: 1.12 < 1.13-beta1 <
-- 1.13-beta2 < 1.13.
function ns.CompareVersions(a, b)
    local pa, ta = ParseVersion(a)
    local pb, tb = ParseVersion(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    if ta == tb then return 0 end
    if ta == "" then return 1 end
    if tb == "" then return -1 end
    local x, y = tonumber(ta:match("%d+") or "") or 0, tonumber(tb:match("%d+") or "") or 0
    if x ~= y then return x < y and -1 or 1 end
    return ta < tb and -1 or 1
end

function ns.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function ns.Split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            break
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return out
end

function ns.PlayerRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- WoW: Forever has no realms players can see, but the game still tags
-- names with the server shard each player happens to live on
-- ("Name-CAMWOWUS1Realm2PvP" for one guildmate, "...US2..." for another),
-- and leaves the tag off names on your own shard. Keyed that way, the same
-- person ended up under two names on different computers, so their shared
-- data never reached their roster row. On Forever a character is known by
-- its name alone (first and second names are unique), so the tag is dropped.
local toc = GetBuildInfo and select(4, GetBuildInfo())
ns.NO_REALMS = (toc and toc >= 16000 and toc < 17000) and true or false

function ns.NormalizeName(name)
    if not name or name == "" then return nil end
    if ns.NO_REALMS then
        local base = ns.Trim(name:match("^([^%-]*)") or name)
        return base ~= "" and base or nil
    end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. ns.PlayerRealm()
end

function ns.ShortName(full)
    if not full then return "" end
    return full:match("^([^%-]+)") or full
end

-- The name to type when whispering or inviting someone. In WoW: Forever
-- characters have a first and second name and there are no realms, so a
-- "-Realm" suffix makes whispers fail ("No player named ... is currently
-- playing"). The realm is kept only for someone on a different realm.
function ns.ChatName(full)
    if not full then return nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if not name then return full end
    if realm == ns.PlayerRealm() or name:find(" ", 1, true) then return name end
    return full
end

-- "Marc Pri" -> "Marc", "Pri". Single names return the name and "".
function ns.SplitName(short)
    local first, second = (short or ""):match("^(%S+)%s+(.+)$")
    if first then return first, second end
    return short or "", ""
end

-- Your own name as the guild roster spells it. Normally "Name-Realm" from
-- UnitName; if the roster lists you differently (found by character GUID in
-- Services/Roster.lua), that spelling wins, so your shared data (version,
-- professions, votes...) lands on your roster row.
function ns.PlayerFullName()
    return ns.selfName or ns.NormalizeName(UnitName("player"))
end

function ns.ClassColor(classFile)
    if classFile and classFile ~= "" then
        local c
        if C_ClassColor and C_ClassColor.GetClassColor then
            local ok, res = pcall(C_ClassColor.GetClassColor, classFile)
            if ok then c = res end
        end
        c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
        if c then return c.r, c.g, c.b end
    end
    return 0.8, 0.8, 0.8
end

function ns.ClassHex(classFile)
    local r, g, b = ns.ClassColor(classFile)
    return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Plays a Blizzard sound by SOUNDKIT name; silently skips names this client lacks.
function ns.PlaySound(kit)
    local id = SOUNDKIT and SOUNDKIT[kit]
    if id and PlaySound then pcall(PlaySound, id) end
end

-- Wraps a script handler so an error is reported once in chat instead of
-- breaking whatever the game was doing (closing windows with Escape, etc.).
local reported = {}
function ns.Safe(fn, where)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local msg = tostring(err)
            if not reported[msg] then
                reported[msg] = true
                ns:Print(("|cffff2020error in %s:|r %s"):format(where or "a handler", msg))
                ns:Print("Please send that line to the addon author. Everything else keeps working.")
            end
        end
    end
end

-- Officers are members whose rank the game marks Officer (Guild Control).
-- The game's Officer setting for your rank (Guild Control).
function ns.IsOfficer()
    if not IsInGuild() then return false end
    if IsGuildLeader and IsGuildLeader() then return true end
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer then
        local ok, yes = pcall(C_GuildInfo.IsGuildOfficer)
        if ok then return yes and true or false end
    end
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        return C_GuildInfo.CanViewOfficerNote() and true or false
    end
    if CanViewOfficerNote then return CanViewOfficerNote() and true or false end
    return false
end

-- Fires OFFICER_CHANGED when the player's officer status changes
-- (promotion, demotion, or guild data arriving after login).
local wasOfficer
local function CheckOfficer()
    local now = ns.IsOfficer()
    if now ~= wasOfficer then
        wasOfficer = now
        ns:Fire("OFFICER_CHANGED", now)
    end
end
ns.CheckOfficer = CheckOfficer

function ns.FormatDate(ts)
    local hour = tonumber(date("%I", ts))
    return date("%b %d, %Y", ts) .. "  " .. hour .. date(":%M %p", ts)
end

-- hours -> "3h", "2d", "4mo"
function ns.FormatLastSeen(hours)
    hours = hours or 0
    if hours < 1 then return "< 1h" end
    if hours < 24 then return ("%dh"):format(hours) end
    local days = math.floor(hours / 24)
    if days < 30 then return ("%dd"):format(days) end
    local months = math.floor(days / 30)
    if months < 12 then return ("%dmo"):format(months) end
    return ("%dy"):format(math.floor(months / 12))
end

-- seconds -> "3 hours", "2 days" (rounded up)
function ns.FormatWait(sec)
    if sec >= 86400 then
        local d = math.ceil(sec / 86400)
        return d == 1 and "1 day" or (d .. " days")
    end
    local h = math.ceil(sec / 3600)
    return h == 1 and "1 hour" or (h .. " hours")
end

function ns.FormatAgo(timestamp)
    if not timestamp then return "never" end
    local secs = math.max(0, time() - timestamp)
    if secs < 90 then return "just now" end
    if secs < 3600 then return ("%d min ago"):format(secs / 60) end
    if secs < 86400 then return ("%d hr ago"):format(secs / 3600) end
    return ("%d days ago"):format(secs / 86400)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    ns.DB:Init()
end)

ns:RegisterEvent("GUILD_ROSTER_UPDATE", function() ns.Debounce("officercheck", 0.5, CheckOfficer) end)
ns:RegisterEvent("PLAYER_GUILD_UPDATE", function() ns.Debounce("officercheck", 0.5, CheckOfficer) end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.Theme:LoadTheme() -- the guild's colours, before any window is built
    ns.Roster:Init()
    ns.Sync:Init()
    ns.RosterLog:Init()
    ns.Recipes:Init()
    ns.Readiness:Init()
    ns.HallOfFame:Init()
    ns.DiscordCode:Init()
    ns.Events:Init()
    ns.HofCheck:Init()
    ns.Sharing:Init()
    ns.Comm:Init()
    ns.Recruit:Init()
    ns.Profile:Init()
    ns.Minimap:Init()
    ns.Options:Init()
    ns.Welcome:Init()
    ns.Communities:Init()
    ns.GuildRoster:Init()
    ns.DNWView:Init()
    ns.WhoWhisper:Init()
    ns.Brand:Init()
    ns:Print(("v%s loaded. Type |cffffffff/ngm|r to open."):format(ns.version))
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function PrintHelp()
    ns:Print("commands:")
    ns:Print("  |cffffffff/ngm|r  - open or close the window")
    ns:Print("  |cffffffff/ngm find <text>|r  - open with a search")
    ns:Print("  |cffffffff/ngm sync|r  - check your data against the guild now, and show sync status")
    ns:Print(("  |cffffffff/ngm audit|r  - open the %s tab (officers)"):format(ns.TabName("audit")))
    ns:Print("  |cffffffff/ngm welcome|r  - the welcome tour (what's where, your sharing choices)")
    ns:Print("  |cffffffff/ngm craft <name>|r  - who in the guild can craft it")
    ns:Print(("  |cffffffff/ngm play|r  - the %s tab: who's around near your level"):format(ns.TabName("together")))
    ns:Print(("  |cffffffff/ngm overview|r  - the %s tab: classes, levels, professions and when the guild plays"):format(ns.TabName("overview")))
    ns:Print(("  |cffffffff/ngm hof|r  - the %s tab: guild leaderboards from everyone's statistics"):format(ns.TabName("hof")))
    ns:Print("  |cffffffff/ngm dnw|r  - the Do Not Whisper list and who was whispered recently")
    ns:Print("  |cffffffff/ngm minimap|r  - show or hide the minimap button")
    ns:Print(("  |cffffffff/ngm recruit|r  - open the %s tab"):format(ns.TabName("recruit")))
    ns:Print("  |cffffffff/ngm options|r  - open the options")
    ns:Print("  |cffffffff/ngm discord|r  - Guild Master: the update code for NGM Peon (ngmpeon.app, Sync tab, step 2)")
    ns:Print("  |cffffffff/ngm discord all|r  - the same, with everything (not just what changed)")
    ns:Print("  |cffffffff/ngm discord setup|r  - the short code for /ngm-guild setup in Discord")
    ns:Print("  |cffffffff/ngm peon|r  - bring in the code from NGM Peon's dashboard (ngmpeon.app, Sync tab, step 3)")
    ns:Print("  |cffffffff/ngm events|r  - the guild's upcoming events from NGM Peon, and where to sign up")
    ns:Print("  |cffffffff/ngm diag|r  - troubleshooting: version, sync, and the addon's hooks into game windows")
    ns:Print("  |cffffffff/ngm reset|r  - reset the window size and position")
end

SLASH_NOOTROPICGM1 = "/ngm"
SLASH_NOOTROPICGM2 = "/nootropic"
SlashCmdList.NOOTROPICGM = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "find" or cmd == "search" then
        ns.UI:Show()
        ns.UI:SetSearch(rest)
    elseif cmd == "diag" then
        local me = ns.PlayerFullName()
        ns:Print(("Version %s, playing as %s%s. Sync: %s."):format(ns.version, me,
            ns.Roster.byName[me] and "" or " (|cffff2020not found on the guild roster|r)", select(2, ns.Sync:Health())))
        ns:Print(("Rank settings (Officer, Invite) of other ranks: %s."):format(ns.Sync:RankFlags(1)
            and "read from the game" or "not given by the game, taken from the Guild Master's addon"))
        ns.Communities:Diagnose()
        ns.GuildRoster:Diagnose()
        ns.WhoWhisper:Diagnose()
        ns.Recruit:Diagnose()
        ns.Accent:Diagnose()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.Options:Open()
    elseif cmd == "recruit" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_RECRUIT)
    elseif cmd == "sync" then
        ns.Comm:Report()
        if ns.Sync:CheckAll() then
            ns.Sync.reportLane = "guild"
            ns:Print("Checking with your guild now...")
        end
        for _, line in ipairs(ns.Sync:StatusLines()) do ns:Print("  " .. line) end
    elseif cmd == "audit" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_AUDIT)
    elseif cmd == "welcome" or cmd == "tour" then
        ns.Welcome:Open()
    elseif cmd == "craft" or cmd == "crafters" or cmd == "recipe" then
        ns.RecipesView:Open({ text = rest })
    elseif cmd == "play" or cmd == "together" then
        ns.UI:OpenTab(ns.UI.TAB_TOGETHER)
    elseif cmd == "overview" or cmd == "census" then
        ns.UI:OpenTab(ns.UI.TAB_OVERVIEW)
    elseif cmd == "hof" or cmd == "fame" or cmd == "halloffame" then
        ns.UI:OpenTab(ns.UI.TAB_HOF)
    elseif cmd == "peon" then
        ns.PeonPasteView:Open()
    elseif cmd == "events" or cmd == "calendar" or cmd == "cal" then
        ns.UI:OpenTab(ns.UI.TAB_EVENTS)
    elseif cmd == "discord" then
        local mode = rest and rest:lower():match("^%s*(%a+)")
        ns.DiscordCodeView:Open((mode == "setup" or mode == "all") and mode or nil)
    elseif cmd == "dnw" then
        ns.DNWView:Toggle()
    elseif cmd == "minimap" then
        ns.Minimap:ToggleShown()
    elseif cmd == "reset" then
        ns.UI:ResetPosition()
        ns:Print("Window size and position reset.")
    else
        PrintHelp()
    end
end

------------------------------------------------------------------------
-- Addon compartment (minimap addon menu)
------------------------------------------------------------------------
function NootropicGuildManager_OnCompartmentClick(_, button)
    if button == "RightButton" then
        ns.Options:Open()
    else
        ns.UI:OpenTab(ns.UI.TAB_ROSTER, true)
    end
end

function NootropicGuildManager_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine("Nootropic Guild Manager")
    GameTooltip:AddLine("Click to open Nootropic Guild Manager.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for options.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NootropicGuildManager_OnCompartmentLeave()
    GameTooltip:Hide()
end
