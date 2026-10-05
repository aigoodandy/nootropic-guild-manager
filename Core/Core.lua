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
-- Performance counters (/ngm perf)
------------------------------------------------------------------------
ns.perf = { started = GetTime() }

function ns.Count(name, n)
    ns.perf[name] = (ns.perf[name] or 0) + (n or 1)
end

local function KB(bytes)
    if bytes >= 1024 * 1024 then return ("%.1f MB"):format(bytes / 1024 / 1024) end
    return ("%.1f KB"):format(bytes / 1024)
end

-- /ngm perf: memory, sync traffic, stored records and redraw counts.
function ns.PerfReport()
    local p = ns.perf
    local secs = math.max(1, GetTime() - p.started)
    local mins = secs / 60
    local function Rate(n) return ("%d (%.1f/min)"):format(n or 0, (n or 0) / mins) end
    ns:Print(("Performance this session (%dh %02dm):"):format(math.floor(secs / 3600), math.floor(secs / 60) % 60))

    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local ok, kb = pcall(GetAddOnMemoryUsage, ns.name)
        if ok and kb then ns:Print("  Memory: " .. KB(kb * 1024)) end
    end

    local st = ns.Sync.stats
    ns:Print(("  Sync: %d sent (%s), %d received (%s), %d applied, %d queued, %d retries, %d dropped"):format(
        st.sent, KB(p.bytesOut or 0), st.received, KB(p.bytesIn or 0), st.applied, ns.Sync:QueueSize(), st.retries, st.dropped))
    ns:Print(("  Sending: %.0f bytes/sec on average (limit %d)"):format((p.bytesOut or 0) / secs, ns.Sync.BYTES_PER_SEC))

    for _, scope in ipairs({ "guild", "officer" }) do
        local store = ns.DB:Guild() and ns.Sync:Store(scope)
        if store then
            local total, byType = 0, {}
            for key in pairs(store) do
                total = total + 1
                local typ = key:match("^(%u+):")
                if typ then byType[typ] = (byType[typ] or 0) + 1 end
            end
            local list = {}
            for typ, n in pairs(byType) do list[#list + 1] = { typ, n } end
            table.sort(list, function(a, b) return a[2] > b[2] end)
            local parts = {}
            for i = 1, math.min(5, #list) do
                local def = ns.Sync.TYPES[list[i][1]]
                parts[i] = ("%s %d"):format(def and def.label or list[i][1], list[i][2])
            end
            ns:Print(("  Stored %s records: %d%s"):format(scope, total, #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
        end
    end

    local positions = 0
    for _ in pairs(ns.Location.positions) do positions = positions + 1 end
    ns:Print(("  Roster: rebuilt %s, redrawn %s"):format(Rate(p.rosterBuilds), Rate(p.rosterRedraws)))
    ns:Print(("  Map: %s positions received, dots redrawn %s, %d guildmates on the map"):format(
        Rate(p.positionsIn), Rate(p.mapRedraws), positions))
    ns:Print(("  Kudos index built %d times"):format(p.kudosIndexBuilds or 0))
end

------------------------------------------------------------------------
-- Tab names in text ("Vote on the Insights tab"): the title officers gave the
-- tab in Options > Officers > Tabs, else its usual name. key: "roster",
-- "recruit", "polls", "tags", "audit" or "reviews".
------------------------------------------------------------------------
local USUAL_TAB_NAMES = { roster = "Roster", recruit = "Recruitment", polls = "Insights", tags = "Tags", audit = "Audit", reviews = "Reviews" }

function ns.TabName(key)
    local UI, DB = ns.UI, ns.DB
    if UI and UI.TabTitle and DB and DB.TAB_KEYS then
        for i, k in ipairs(DB.TAB_KEYS) do
            if k == key then
                local ok, title = pcall(UI.TabTitle, UI, i)
                if ok and title then return title end
            end
        end
    end
    return USUAL_TAB_NAMES[key] or key
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
    ns.Polls:Init()
    ns.Profile:Init()
    ns.Minimap:Init()
    ns.Options:Init()
    ns.Communities:Init()
    ns.WhoWhisper:Init()
    ns.Brand:Init()
    ns.MapPins:Init()
    ns:Print(("v%s loaded. Type |cffffffff/ngm|r to open."):format(ns.version))
end)

------------------------------------------------------------------------
-- /ngm inspect: what the mouse is over (for copying Blizzard's look):
-- the frame's name, size and parent, and every texture on it and on its
-- child frames (atlas or file, layer, size, texture coordinates).
------------------------------------------------------------------------
local function Fmt(n) return n and ("%.0f"):format(n) or "?" end

-- Prints a line and keeps it in the saved data (NootropicGuildManagerDB.inspectLog),
-- which the game writes to WTF\Account\...\SavedVariables on /reload or logout,
-- so the output can be read without copying it out of chat.
local INSPECT_KEEP = 300
local function Out(text)
    ns:Print(text)
    if not NootropicGuildManagerDB then return end
    local log = NootropicGuildManagerDB.inspectLog or {}
    NootropicGuildManagerDB.inspectLog = log
    log[#log + 1] = text
    while #log > INSPECT_KEEP do table.remove(log, 1) end
end

local function PrintRegions(frame, indent)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = atlas and ("atlas " .. atlas) or ("file " .. tostring(r:GetTexture()))
            local layer, sub = r:GetDrawLayer()
            local coords = ""
            if not atlas and r.GetTexCoord then
                local a, b, c, d, e, f2, g, h = r:GetTexCoord()
                if a and (a ~= 0 or b ~= 0 or c ~= 0 or d ~= 1 or e ~= 1 or f2 ~= 0 or g ~= 1 or h ~= 1) then
                    coords = (" coords %.3f %.3f %.3f %.3f"):format(a, e, b, d) -- left right top bottom
                end
            end
            local point, rel, relPoint, x, y = r:GetPoint(1)
            Out(("%s%s %s/%s %sx%s%s%s %s"):format(indent, tex, tostring(layer), tostring(sub or 0),
                Fmt(r:GetWidth()), Fmt(r:GetHeight()), coords, r:IsShown() and "" or " (hidden)",
                point and ("@" .. point .. " " .. Fmt(x) .. "," .. Fmt(y)) or ""))
            -- masks that trim this texture's shape
            for m = 1, (r.GetNumMaskTextures and r:GetNumMaskTextures() or 0) do
                local mask = r:GetMaskTexture(m)
                if mask then
                    local matlas = mask.GetAtlas and mask:GetAtlas()
                    local mp, _, _, mx, my = mask:GetPoint(1)
                    Out(("%s  masked by %s %sx%s %s"):format(indent,
                        matlas and ("atlas " .. matlas) or ("file " .. tostring(mask:GetTexture())),
                        Fmt(mask:GetWidth()), Fmt(mask:GetHeight()), mp and ("@" .. mp .. " " .. Fmt(mx) .. "," .. Fmt(my)) or ""))
                end
            end
        elseif r:GetObjectType() == "MaskTexture" then
            local matlas = r.GetAtlas and r:GetAtlas()
            local mp, _, _, mx, my = r:GetPoint(1)
            Out(("%smask %s %sx%s %s"):format(indent, matlas and ("atlas " .. matlas) or ("file " .. tostring(r:GetTexture())),
                Fmt(r:GetWidth()), Fmt(r:GetHeight()), mp and ("@" .. mp .. " " .. Fmt(mx) .. "," .. Fmt(my)) or ""))
        end
    end
end

function ns.InspectUnderMouse()
    local f = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
    if not f or f == WorldFrame then
        Out("Hover a window part, then type /ngm inspect and press Enter (keep the mouse still).")
        return
    end
    local parent = f:GetParent()
    Out("---- /ngm inspect " .. date("%H:%M:%S"))
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if point then
        Out(("  placed %s of %s %s, offset %s,%s"):format(point,
            rel and (rel.GetDebugName and rel:GetDebugName() or tostring(rel:GetName())) or "?", tostring(relPoint), Fmt(x), Fmt(y)))
    end
    Out(("Frame: %s (%s) %sx%s, parent %s"):format(f.GetDebugName and f:GetDebugName() or tostring(f:GetName()),
        f:GetObjectType(), Fmt(f:GetWidth()), Fmt(f:GetHeight()),
        parent and (parent.GetDebugName and parent:GetDebugName() or tostring(parent:GetName())) or "none"))
    PrintRegions(f, "  ")
    for _, child in ipairs({ f:GetChildren() }) do
        Out(("  child %s %sx%s"):format(child.GetDebugName and child:GetDebugName() or tostring(child:GetName()),
            Fmt(child:GetWidth()), Fmt(child:GetHeight())))
        PrintRegions(child, "    ")
    end
    local hl = f.GetHighlightTexture and f:GetHighlightTexture()
    if hl then Out("  highlight: " .. tostring(hl.GetAtlas and hl:GetAtlas() or hl:GetTexture())) end
    local ck = f.GetCheckedTexture and f:GetCheckedTexture()
    if ck then Out("  checked: " .. tostring(ck.GetAtlas and ck:GetAtlas() or ck:GetTexture())) end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function PrintHelp()
    ns:Print("commands:")
    ns:Print("  |cffffffff/ngm|r  - open or close the roster")
    ns:Print("  |cffffffff/ngm find <text>|r  - open with a search")
    ns:Print("  |cffffffff/ngm sync|r  - sync with guildmates now and show sync stats")
    ns:Print(("  |cffffffff/ngm audit|r  - open the %s tab (officers)"):format(ns.TabName("audit")))
    ns:Print(("  |cffffffff/ngm insights|r  - open the %s tab (goals, polls and stats)"):format(ns.TabName("polls")))
    ns:Print(("  |cffffffff/ngm reviews|r  - open the %s tab (review the guild)"):format(ns.TabName("reviews")))
    ns:Print("  |cffffffff/ngm minimap|r  - show or hide the minimap button")
    ns:Print(("  |cffffffff/ngm recruit|r  - open the %s tab"):format(ns.TabName("recruit")))
    ns:Print("  |cffffffff/ngm mini|r  - show or hide the small recruiting bar")
    ns:Print("  |cffffffff/ngm compact|r  - show or hide the compact guild roster")
    ns:Print("  |cffffffff/ngm export|r  - copy the roster as text for a spreadsheet or .csv file")
    ns:Print("  |cffffffff/ngm options|r  - open the options")
    ns:Print("  |cffffffff/ngm diag|r  - troubleshoot the Guild & Communities shortcut")
    ns:Print("  |cffffffff/ngm perf|r  - memory, sync traffic and how often things redraw")
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
        ns.WhoWhisper:Diagnose()
        ns.Roster:Diagnose()
    elseif cmd == "perf" then
        ns.PerfReport()
    elseif cmd == "inspect" then
        ns.InspectUnderMouse()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.Options:Open()
    elseif cmd == "recruit" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_RECRUIT)
    elseif cmd == "mini" then
        ns.RecruitMini:Toggle()
    elseif cmd == "compact" then
        ns.CompactRoster:Toggle()
    elseif cmd == "export" then
        ns.Export:Open()
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
    elseif cmd == "insights" or cmd == "poll" or cmd == "polls" or cmd == "stats" or cmd == "goals" then
        ns.UI:Show()
        ns.UI:SelectTab(ns.UI.TAB_POLLS)
    elseif cmd == "review" or cmd == "reviews" then
        ns.UI:Show()
        if not ns.UI:IsTabAvailable(ns.UI.TAB_REVIEWS) then
            ns:Print("Guild reviews are turned off by the officers.")
        end
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
