-- Test: install reminders (who can be reminded, again after an hour, a player's
-- other characters counting,
-- the record others see) and Discord names shown with an @.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
local guild = { members = {}, sync = { guild = {}, officer = {} } }
local settings = {}
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
local printed = {}
function ns:Print(m) printed[#printed + 1] = m end
function ns.Debounce(_, _, fn) fn() end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.IsOfficer() return false end
function ns.PlayerFullName() return "Marc Priest" end
function ns.NormalizeName(n) return n end
function ns.ShortName(n) return n end
function ns.ChatName(n) return n end
function ns.FormatAgo(t) return (math.floor((NOW - t) / 86400)) .. " days ago" end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return settings end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
ns.Roster = { byName = { ["Marc Priest"] = { rankIndex = 0 }, ["Grud Sama"] = { rankIndex = 4 }, ["Probably Shawn"] = { rankIndex = 1 } } }
C_Timer = { After = function() end }
GetTime = function() return 100 end
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
local whispers = {}
ns.Recruit = { SendWhisper = function(msg, to) whispers[#whispers + 1] = { msg, to } end,
  Format = function(_, text, p) return (text:gsub("%$first", (p.short:match("^(%S+)")))) end }
assert(loadfile(ROOT .. "/Services/InstallReminder.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Profile.lua"))("NGM", ns)
local IR, PF = ns.InstallReminder, ns.Profile

local grud = { full = "Grud Sama", short = "Grud Sama", online = true }
local me = { full = "Marc Priest", short = "Marc Priest", online = true, isSelf = true, hasAddon = true }
local shawn = { full = "Probably Shawn", short = "Probably Shawn", online = true, hasAddon = true }
local off = { full = "Offline Guy", short = "Offline Guy", online = false }

assert(not IR:MenuItem(me) and not IR:MenuItem(shawn), "no reminder for you or addon users")
assert(not IR:Can(off), "offline: can't whisper")
assert(IR:Can(grud))
assert(#IR:Message(grud) <= 255 and IR:Message(grud):find("^Hi Grud!"), IR:Message(grud))
assert(IR:Preview(grud):find(IR:Message(grud), 1, true), "the tooltip shows the exact whisper")
assert(IR:MenuItem(grud).tooltip.text == IR:Preview(grud))
assert(IR:Send(grud))
assert(#whispers == 1 and whispers[1][2] == "Grud Sama")
local t, by = IR:Reminded("Grud Sama")
assert(t == NOW and by == "Marc Priest")
local ok, why = IR:Can(grud)
assert(not ok and why:find("You reminded them"), why)
assert(IR:Preview(grud) == why, "after sending, the tooltip says why it's greyed out")
assert(not IR:Send(grud) and #whispers == 1, "not twice within the hour")
assert(IR:StatusLine(grud):find("^Reminded to install by Marc Priest"))
-- an hour later it can be sent again
NOW = NOW + 3601
assert(IR:Can(grud), "again after an hour")
assert(IR:Preview(grud):find("Click to send it again", 1, true))
assert(IR:MenuItem(grud).text == "Remind again to install the addon")
-- an alt of a reminded main shows reminded, and can be reminded again
local alts = { ["Grud Sama"] = { "Grud Alt" } }
ns.DB.RootOf = function(_, f) return f == "Grud Alt" and "Grud Sama" or f end
ns.DB.GetAltsOf = function(_, f) local t = {} for i, v in ipairs(alts[f] or {}) do t[i] = v end return t end
local alt = { full = "Grud Alt", short = "Grud Alt", online = true }
local at, aby, via = IR:Reminded("Grud Alt")
assert(at == NOW - 3601 and aby == "Marc Priest" and via == "Grud Sama", "the main's reminder counts")
assert(IR:StatusLine(alt):find("(on Grud Sama)", 1, true), IR:StatusLine(alt))
assert(IR:Send(alt) and #whispers == 2 and whispers[2][2] == "Grud Alt", "resent to the alt")
assert(not IR:Can(grud), "and the main shows it too, within the hour")
ns.DB.RootOf, ns.DB.GetAltsOf = nil, nil
-- another guildmate's reminder arrives; 31 days later it's gone
ns.Sync:OnMessage(table.concat({ ns.Sync.PROTO, "R", "IR:Offline Guy", tostring(NOW - 31 * 86400), "Grud Sama", "", tostring(NOW - 31 * 86400) }, "\t"), "GUILD", "Grud Sama")
assert(not IR:Reminded("Offline Guy"), "expired after 30 days")
-- forged reminders are refused: in someone else's name, about a stranger, or with a junk time
local function forge(sender, member, author, v)
  ns.Sync:OnMessage(table.concat({ ns.Sync.PROTO, "R", "IR:" .. member, tostring(NOW - 5), author, "", v or tostring(NOW - 5) }, "\t"), "GUILD", sender)
  return guild.sync.guild["IR:" .. member]
end
assert(not forge("Grud Sama", "Probably Shawn", "Marc Priest"), "in someone else's name")
assert(not forge("Grud Sama", "Total Stranger", "Grud Sama"), "not a guildmate")
assert(not forge("Grud Sama", "Probably Shawn", "Grud Sama", "999999999999"), "junk time")
assert(forge("Grud Sama", "Probably Shawn", "Grud Sama"), "their own reminder is fine")

-- custom text
IR:SetText("Yo $first, grab the addon!")
assert(IR:Message(grud) == "Yo Grud, grab the addon!")
IR:SetText("")
assert(IR:Text() == IR.DEFAULT)

-- Discord names
assert(PF.DiscordLabel("keasbeexd") == "@keasbeexd")
assert(PF.DiscordLabel("@keasbeexd") == "@keasbeexd" and PF.DiscordLabel("@@x") == "@x")
ns.DB.GetMember = function(_, f) return guild.members[f] end
ns.Sync.CanWrite = function() return true end
PF:SetContact("Marc Priest", "@keasbeexd", "")
assert(ns.Sync:Value("CN:Marc Priest") == "keasbeexd;", "saved without the @")
print("OK")
