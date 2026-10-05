--[[
    Nootropic Guild Manager - Core
    Namespace, internal events/callbacks, shared utilities and slash commands.
]]
local ADDON_NAME, ns = ...
_G.NootropicGuildManager = ns -- exposed for /dump debugging

ns.name = ADDON_NAME
ns.GOLD = "|cffffd100"
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

-- -1, 0 or 1 comparing versions like "1.9" and "1.10" part by part.
-- Anything that isn't a number counts as 0 ("dev" < "1.0").
function ns.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("[^%.]+") do pa[#pa + 1] = tonumber(n) or 0 end
    for n in tostring(b or ""):gmatch("[^%.]+") do pb[#pb + 1] = tonumber(n) or 0 end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
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

function ns.NormalizeName(name)
    if not name or name == "" then return nil end
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

function ns.PlayerFullName()
    return ns.NormalizeName(UnitName("player"))
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
                ns:Print(("|cffff5555error in %s:|r %s"):format(where or "a handler", msg))
                ns:Print("Please send that line to the addon author. Everything else keeps working.")
            end
        end
    end
end

-- Officers are members whose rank can read officer notes.
function ns.IsOfficer()
    if not IsInGuild() then return false end
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
    ns.Roster:Init()
    ns.Sync:Init()
    ns.Comm:Init()
    ns.Recruit:Init()
    ns.Location:Init()
    ns.Reviews:Init()
    ns.Minimap:Init()
    ns.Options:Init()
    ns.Communities:Init()
    ns.Brand:Init()
    ns.MapPins:Init()
    if ns.DB.imported then
        ns:Print("Imported your Guild Ledger data. You can now delete the old GuildLedger folder from Interface/AddOns.")
    end
    ns:Print(("v%s loaded. Type |cffffffff/ngm|r to open."):format(ns.version))
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function PrintHelp()
    ns:Print("commands:")
    ns:Print("  |cffffffff/ngm|r  - open or close the roster")
    ns:Print("  |cffffffff/ngm find <text>|r  - open with a search")
    ns:Print("  |cffffffff/ngm sync|r  - sync with guildmates now and show sync stats")
    ns:Print("  |cffffffff/ngm audit|r  - open the Audit tab (officers)")
    ns:Print("  |cffffffff/ngm reviews|r  - open the Reviews tab (review the guild)")
    ns:Print("  |cffffffff/ngm minimap|r  - show or hide the minimap button")
    ns:Print("  |cffffffff/ngm recruit|r  - open the Recruitment tab")
    ns:Print("  |cffffffff/ngm options|r  - open the options")
    ns:Print("  |cffffffff/ngm diag|r  - troubleshoot the Guild & Communities shortcut")
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
        ns.Communities:Diagnose()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.Options:Open()
    elseif cmd == "recruit" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_RECRUIT)
    elseif cmd == "sync" then
        ns.Comm:Report()
        local started = ns.Sync:Exchange(true)
        local st = ns.Sync.stats
        ns:Print(started and "Comparing data with guildmates now." or "A sync just ran; it repeats automatically every few minutes.")
        ns:Print(("Sync this session: %d sent, %d received, %d applied, %d queued, %d dropped."):format(
            st.sent, st.received, st.applied, ns.Sync:QueueSize(), st.dropped))
    elseif cmd == "audit" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_AUDIT)
    elseif cmd == "review" or cmd == "reviews" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_REVIEWS)
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
    GameTooltip:AddLine("Click to open the guild roster.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for options.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NootropicGuildManager_OnCompartmentLeave()
    GameTooltip:Hide()
end
