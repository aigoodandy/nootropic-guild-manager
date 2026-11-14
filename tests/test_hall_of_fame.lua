-- Test: Hall of Fame: reading statistics, monthly snapshots across month
-- changes, the shared record, periods as of a later month, turning sharing
-- off, and the leaderboards (alts always added up under their main).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { Widgets = {} }
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end function ns:Print(m) print("  [print] " .. m) end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return fn end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.IsOfficer() return false end
function ns.PlayerFullName() return "Me Self-R" end
function ns.NormalizeName(n) return n end
local settings = {}
ns.DB = { PERM_BY_TYPE = {}, Guild = function() return guild end, Now = function() return NOW end,
  Settings = function() return settings end, EnsureMember = function(_, f) guild.members[f] = guild.members[f] or {} return guild.members[f] end,
  HasPerm = function() return true end }
local function m(full, class, main) return { full = full, short = full:gsub("%-.*", ""), classFile = class, main = main } end
ns.Roster = { members = {
  m("Me Self-R", "MAGE"),
  m("Big Main-R", "WARRIOR"),
  m("Big Alt-R", "PRIEST", "Big Main-R"),
  m("No Addon-R", "ROGUE"),
} }
ns.Roster.byName = {}
for _, e in ipairs(ns.Roster.members) do ns.Roster.byName[e.full] = e end
C_Timer = { After = function() end, NewTicker = function() end }
GetTime = function() return 1 end
IsInGuild = function() return true end
ns.Data = {}
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
assert(loadfile(ROOT .. "/Services/Sharing.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/HallOfFame.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/UI/HallOfFameView.lua"))("NGM", ns)
local HF, HV = ns.HallOfFame, ns.HallOfFameView

-- parsing what GetStatistic returns
assert(HF.Parse("1,234") == 1234 and HF.Parse("--") == nil and HF.Parse("7") == 7)
assert(HF.Parse("12|TInterface\\MoneyFrame\\UI-GoldIcon:0|t") == nil, "money is ignored")
assert(HF.Parse("282 (Humanoid)") == 282)
assert(HF.PrevMonth(202601) == 202512 and HF.PrevMonth(202611) == 202610)

-- your own statistics
local stats = { [98] = "100", [60] = "10", [1197] = "1,000", [15031] = "2", [1098] = "3" }
GetStatistic = function(id) return stats[id] or "--" end
local month = 202611
HF.Month = function() return month end
HF:Publish()
local r = HF.Decode(ns.Sync:Value("HF:Me Self-R"))
print("all", r.all.quests, r.all.kills, r.all.bosses, "this month", r.this.quests)
assert(r.all.quests == 100 and r.all.kills == 1000 and r.all.bosses == 5 and r.all.deaths == 10)
assert(next(r.this) == nil, "first read: nothing this month yet")

-- more play the same month
stats[98], stats[60] = "130", "12"
HF:Publish()
r = HF.Decode(ns.Sync:Value("HF:Me Self-R"))
assert(r.this.quests == 30 and r.this.deaths == 2)

-- next month: last month kept, this month starts over
month = 202612
stats[98] = "150"
HF:Publish()
r = HF.Decode(ns.Sync:Value("HF:Me Self-R"))
print("december", r.this.quests, "november", r.last.quests, r.lastMonth)
assert(r.last.quests == 50 and r.lastMonth == 202611 and next(r.this) == nil)
stats[98] = "160"
HF:Publish()
assert(HF:For("Me Self-R", "month").quests == 10)
assert(HF:For("Me Self-R", "last").quests == 50)

-- read in January from that December record: December becomes "last month"
assert(HF:For("Me Self-R", "last", 202701).quests == 10)
assert(next(HF:For("Me Self-R", "month", 202701)) == nil)
assert(next(HF:For("Me Self-R", "last", 202702)) == nil)

-- skipping a month: no "last month"
month = 202702
HF:Publish()
r = HF.Decode(ns.Sync:Value("HF:Me Self-R"))
assert(r.lastMonth == 0 and next(r.last) == nil)

-- a statistic the game reset doesn't go negative
stats[98] = "5"
HF:Publish()
assert((HF:For("Me Self-R", "month").quests or 0) == 0)

-- guildmates' records
month = 202702
local function put(full, all, this)
  guild.sync.guild["HF:" .. full] = { v = HF.Encode(202702, all, this, 0, {}), t = 1, a = full }
end
put("Big Main-R", { quests = 300, deaths = 5 }, { quests = 20 })
put("Big Alt-R", { quests = 50, deaths = 40, hugs = 3 }, {})

local b = HV:Boards()
print("sharing", b.sharing, "of", b.people, "top quests", b.boards.quests[1].e.short, b.boards.quests[1].n)
assert(b.people == 3 and b.sharing == 2, "No Addon counted, not sharing")
assert(b.boards.quests[1].e.short == "Big Main" and b.boards.quests[1].n == 350, "alt added to main")
assert(b.boards.deaths[1].n == 45 and b.boards.hugs[1].n == 3)
assert(b.mine == "Me Self-R" and b.totals.quests == 355)


settings.hofPeriod = "month"
b = HV:Boards()
assert(#b.boards.quests == 1 and b.boards.quests[1].n == 20)
settings.hofPeriod = nil

-- statistics are public (Blizzard): always shared, no switch
ns.Sharing:Set("stats", false)
assert(ns.Sharing:Get("stats") == true, "no switch for statistics")

assert(HV.Number(1234567) == "1,234,567" and HV.Number(12) == "12" and HV.Number(123) == "123")
print("OK")
