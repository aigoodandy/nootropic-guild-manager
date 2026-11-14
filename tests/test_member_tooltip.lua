-- Test: the member tooltip (the same everywhere: the addon's lists, Play
-- Together, the game's guild roster) shows only main/alt, spec, role, the two
-- main professions, Discord and your private note.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
ns.Theme = { C = { yellow = { 0.98, 0.74, 0.18 } } } -- UI/Theme.lua sets this
local lines = {}
GameTooltip = {
  AddLine = function(_, t) lines[#lines + 1] = t end,
  AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " = " .. r end,
  SetOwner = function() end, Show = function() end, IsShown = function() return true end,
}
ns.Widgets = {}
ns.InstallReminder = { StatusLine = function(_, e) return e.reminded and "Reminded to install by Marc 1 day ago" or nil end }
function ns:On() end function ns:RegisterEvent() end
function ns.ClassColor() return 1, 1, 1 end
assert(loadfile(ROOT .. "/Core/Data.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/UI/RosterView.lua"))("NGM", ns)
local RV = ns.RosterView
local e = {
  short = "Marc", hasAddon = true, version = "2.12.0", level = 30, className = "Priest", isAlt = false, alts = { "Marc Druid" },
  spec = "Discipline", roleList = { "Healer" }, discord = "@keasbeexd",
  profs = { { name = "First Aid", rank = 80, max = 150 }, { name = "Herbalism", rank = 30, max = 75 },
            { name = "Cooking", rank = 1, max = 75 }, { name = "Alchemy", rank = 10, max = 75 }, { name = "Fishing", rank = 3, max = 75 } },
}
RV:AddMemberLines(e)
local text = table.concat(lines, "\n")
print(text)
assert(text:find("Main = ", 1, true) and text:find("1 alt", 1, true), "main, with alts counted")
assert(text:find("Spec = Discipline", 1, true) and text:find("Role = Healer", 1, true), "spec and role")
assert(text:find("Herbalism", 1, true) and text:find("Alchemy", 1, true), "the two main professions")
assert(not text:find("First Aid", 1, true) and not text:find("Cooking", 1, true) and not text:find("Fishing", 1, true), "no secondary skills")
assert(text:find("Discord = @keasbeexd", 1, true), "Discord")
assert(text:find("Addon version = 2.12.0", 1, true), "their addon version")
assert(not text:find("Usually", 1, true) and not text:find("Rank", 1, true) and not text:find("Reminded", 1, true), "nothing else")
-- our lists start the way the game's guild roster does
lines = {}
RV:ShowRowTooltip({}, { full = "Faldorn Xzar", rank = "Trial", level = 29, race = "Tauren", className = "Druid",
  zone = "Ashenvale", isAlt = false, alts = {}, profs = {} })
assert(lines[1] == "Faldorn Xzar" and lines[2] == "Trial" and lines[3] == "Level 29 Tauren Druid" and lines[4] == "Ashenvale",
  "name, rank, level race class, zone: " .. table.concat(lines, " | "))
lines = {}
RV:AddMemberLines({ isAlt = true, mainShort = "Mykkie", profs = {} })
assert(lines[1] == "Alt of = Mykkie", "alt of whom")
assert(lines[#lines] == "Not reminded to install the addon yet", "no addon, not reminded")
lines = {}
RV:AddMemberLines({ profs = {}, reminded = true })
assert(lines[#lines] == "Reminded to install by Marc 1 day ago", "no addon, reminded")
print("OK")
