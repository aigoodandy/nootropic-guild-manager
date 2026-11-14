-- Test: Overview census: mains counted once (active if any character was),
-- the activity window, Count alts, professions across alts, and the
-- play-time heatmap (hours merged per person, hidden people counted but not named).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = { Widgets = {}, Data = { CLASSES = { "WARRIOR", "MAGE" }, PROFESSIONS = {} } }
function ns:On() end
local settings = {}
ns.DB = { Settings = function() return settings end }
local hidden = { ["Quiet One-R"] = true }
ns.Sharing = { HiddenFromTogether = function(_, f) return hidden[f] or false end }
-- hour index (0 = Monday 00:00) -> true
local hours = {
    ["Big Main-R"] = { [20] = true },        -- Monday 20:00 (block 10)
    ["Big Alt-R"]  = { [21] = true, [44] = true }, -- Monday 21:00 (block 10), Tuesday 20:00
    ["Quiet One-R"] = { [20] = true },
}
ns.Profile = { Hours = function(_, f) return hours[f] end }
local function m(full, class, level, online, lastOnline, main, profs)
    local p = {}
    for i, n in ipairs(profs or {}) do p[i] = { name = n } end
    return { full = full, short = full:gsub("%-.*", ""), classFile = class, level = level,
             online = online, lastOnline = lastOnline or 0, main = main, profs = p }
end
ns.Roster = { members = {
    m("Big Main-R", "WARRIOR", 60, false, 24 * 60, nil, { "Mining" }),          -- offline 60 days...
    m("Big Alt-R", "MAGE", 35, true, 0, "Big Main-R", { "Tailoring", "Mining" }), -- ...but the alt is on
    m("Quiet One-R", "MAGE", 60, false, 24 * 3),
    m("Gone Away-R", "WARRIOR", 12, false, 24 * 200),
    m("Lost Alt-R", "MAGE", 20, false, 24 * 2, "Left Guild-R"),                 -- main not in the guild
} }

assert(loadfile(ROOT .. "/UI/OverviewView.lua"))("NGM", ns)
local OV = ns.OverviewView

-- 30 days, mains only
local c = OV:Census()
print("people", c.people, "warriors", c.classes.WARRIOR, "mages", c.classes.MAGE)
assert(c.people == 3, "Big Main (via alt), Quiet One, Lost Alt")
assert(c.classes.WARRIOR == 1 and c.classes.MAGE == 2)
assert(c.levels[7] == 2 and c.levels[3] == 1, "two at 60 (Big Main, Quiet One), Lost Alt in 20-29")
assert(c.profs.Mining == 1 and c.profs.Tailoring == 1, "Mining counted once for Big Main and alt")
assert(c.sharing == 2)
assert(c.heat[10] == 2, "Monday 20-22: Big Main (merged) and Quiet One")
assert(c.heat[12 + 10] == 1, "Tuesday 20-22: Big Main via the alt")
assert(#c.heatNames[10] == 2, "everyone sharing their hours is named (an old Play Together hide no longer hides)")
assert(c.heatMax == 2)

-- everyone
settings.overviewDays = 0
c = OV:Census()
print("everyone", c.people)
assert(c.people == 4)

-- count alts, 30 days
settings.overviewDays, settings.overviewAlts = 30, true
c = OV:Census()
print("characters", c.people, "mining", c.profs.Mining)
assert(c.people == 3, "Big Alt, Quiet One, Lost Alt (Big Main offline 60 days)")
assert(c.profs.Mining == 1 and c.classes.WARRIOR == nil)

-- 7 days, mains only
settings.overviewDays, settings.overviewAlts = 7, nil
c = OV:Census()
print("7 days", c.people)
assert(c.people == 3)
print("OK")
