-- Test: Play Together lists: level range, your own characters left out, your zone first, usually-on-now.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = { Widgets = {}, Data = {} }
function ns:On() end
local settings = {}
ns.DB = { Settings = function() return settings end }
function ns.PlayerFullName() return "Me Main-R" end
local usual = { ["Night Owl-R"] = true, ["Off Far-R"] = true }
hidden = {}
ns.Sharing = { HiddenFromTogether = function(_, f) return hidden[f] or false end }
ns.Profile = { UsuallyOnNow = function(_, f) return usual[f] or false end }
local function m(full, level, online, zone, main) return { full = full, short = full:gsub("%-.*", ""), level = level, online = online, zone = zone or "", main = main } end
ns.Roster = { members = {
  m("Me Main-R", 20, true, "Westfall"),
  m("My Alt-R", 21, true, "Duskwood", "Me Main-R"),
  m("Near Zone-R", 23, true, "Westfall"),
  m("Near Other-R", 19, true, "Redridge"),
  m("Too High-R", 40, true, "Westfall"),
  m("Night Owl-R", 30, false),
  m("Off Far-R", 55, false),
  m("Off Never-R", 20, false),
} }
ns.Roster.byName = {} for _, e in ipairs(ns.Roster.members) do ns.Roster.byName[e.full] = e end
ns.Roster.members[1].isSelf = true
assert(loadfile(ROOT .. "/UI/TogetherView.lua"))("NGM", ns)
local TV = ns.TogetherView
local function names(list) local t = {} for i, e in ipairs(list) do t[i] = e.short end return table.concat(t, ", ") end
local L = TV:Lists()
print("range 5 online:", names(L.online)); print("usual:", names(L.usual))
assert(names(L.online) == "Near Zone, Near Other" and names(L.usual) == "Night Owl, Off Far")
settings.playRange = 0
L = TV:Lists(); print("any level online:", names(L.online))
assert(names(L.online) == "Near Zone, Too High, Near Other")
hidden["Near Zone-R"] = true -- an old (2.12) hide: no longer hides (online and level are on the roster)
L = TV:Lists(); print("old hide ignored:", names(L.online))
assert(names(L.online) == "Near Zone, Too High, Near Other")
print("OK")
