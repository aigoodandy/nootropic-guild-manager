--[[
    Nootropic Guild Manager - Install reminders
    A one-click whisper to a guildmate who doesn't run the addon yet,
    saying why it's worth having and where to get it. Anyone in the guild
    can send one, from the Find tab's right-click menu, the game's guild
    roster menu, or the profile.

      IR:<member> = "<time>"   who reminded them (the record's author) and when

    Shared, so the whole guild sees who's been asked: nobody is reminded
    twice within 30 days (the record expires then). A reminder to one of a
    player's characters counts for their mains and alts too, so the others
    show as reminded. Sent only by your click, never automatically. The text is yours to
    change (Settings().installReminder).
]]
local _, ns = ...
local IR = {}
ns.InstallReminder = IR

IR.KEEP = 30 * 86400
IR.DEFAULT = "Hi $first! Our guild uses Nootropic Guild Manager, a free addon: see who can craft what, "
    .. "who's on near your level, guild profiles and our Hall of Fame. Get it on CurseForge, Wago or WowUp "
    .. "(search Nootropic Guild Manager), then type /ngm."

function IR:Text()
    local t = ns.DB:Settings().installReminder
    return (t and t ~= "") and t or self.DEFAULT
end

function IR:SetText(text)
    text = ns.Trim(text or "")
    ns.DB:Settings().installReminder = (text ~= "" and text ~= self.DEFAULT) and text or nil
end

local function Own(full)
    local rec = full and ns.Sync:Get("IR:" .. full)
    if not rec or (rec.v or "") == "" then return nil end
    if rec.t < ns.DB:Now() - IR.KEEP then return nil end
    return rec
end

-- When and by whom `full` (or another of the same player's characters) was
-- last reminded, within 30 days: t, by, and which character got it. Or nil.
function IR:Reminded(full)
    if not full then return nil end
    local best, via = Own(full), full
    local DB = ns.DB
    if DB.RootOf and DB.GetAltsOf then
        local root = DB:RootOf(full)
        local family = DB:GetAltsOf(root)
        family[#family + 1] = root
        for _, name in ipairs(family) do
            local rec = name ~= full and Own(name)
            if rec and (not best or rec.t > best.t) then best, via = rec, name end
        end
    end
    if not best then return nil end
    return best.t, best.a, via
end

local function Who(by) return (by == ns.PlayerFullName()) and "You" or ns.ShortName(by or "?") end

-- Can you remind `e` right now? true, or false and why (for menus and tooltips).
function IR:Can(e)
    if not e then return false, "Unknown member." end
    if e.isSelf then return false, "That's you." end
    if e.hasAddon then return false, "Already uses the addon." end
    local t, by = self:Reminded(e.full)
    if t then return false, ("%s reminded them %s."):format(Who(by), ns.FormatAgo(t)) end
    if not e.online then return false, "Only while they're online (it's a whisper)." end
    return true
end

-- One line for tooltips: "Reminded by Marc 3 days ago", or nil.
function IR:StatusLine(e)
    if not e or e.hasAddon then return nil end
    local t, by, via = self:Reminded(e.full)
    if not t then return nil end
    return ("Reminded to install by %s %s%s"):format(ns.ShortName(by or "?"), ns.FormatAgo(t),
        via ~= e.full and (" (on " .. ns.ShortName(via) .. ")") or "")
end

function IR:Message(e)
    return ns.Recruit:Format(self:Text(), { full = e.full, short = e.short, classFile = e.classFile,
        className = e.className, level = e.level, zone = e.zone })
end

-- Sends the reminder (call from a click). true, or false and why.
function IR:Send(e)
    local ok, why = self:Can(e)
    if not ok then
        ns:Print(why)
        return false, why
    end
    local msg = self:Message(e)
    if msg == "" then return false, "The reminder text is empty." end
    ns.Recruit.SendWhisper(msg, ns.ChatName(e.full))
    ns.Sync:Set("IR:" .. e.full, tostring(ns.DB:Now()))
    ns:Print(("Reminded %s to install the addon."):format(e.short))
    return true
end

-- The tooltip text for the button and menu entry: why it's unavailable, or
-- the exact whisper they'd get.
function IR:Preview(e)
    local ok, why = self:Can(e)
    if not ok then return why end
    return "They'll get:\n|cffff80ff" .. self:Message(e) .. "|r\n\nOnce per 30 days, for the whole guild (alts count). Change the text in Options > Install Reminder."
end

-- Menu items for a member (Find tab and the game's roster), or nil when
-- they already use the addon.
function IR:MenuItem(e)
    if not e or e.hasAddon or e.isSelf then return nil end
    local ok, why = self:Can(e)
    return { text = "Remind to install the addon", disabled = not ok,
             tooltip = { title = "Remind to install the addon", text = self:Preview(e) },
             func = function() IR:Send(e) end }
end
