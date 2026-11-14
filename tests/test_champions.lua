-- Test: Social Butterfly (15-minute blocks with someone else talking, 8 a day,
-- spam counts once), last month's champions (winner takes all, ties share),
-- champion wins tallied per person and shared, Most Champion Wins not summed
-- across a person's characters.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { Widgets = {} }
ns.GOLD, ns.ORANGE, ns.BLUE = "|cfffabd2f", "|cfffe8019", "|cff83a598" -- Core.lua sets these
local guild = { members = {}, sync = { guild = {}, officer = {} } }
local settings = {}
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end function ns:Print() end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return fn end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
iAmOfficer = false
function ns.IsOfficer() return iAmOfficer end
local me = "Marc Priest"
function ns.PlayerFullName() return me end
function ns.NormalizeName(n) return n end
function ns.ShortName(n) return n end
function ns.FormatAgo(t) return "just now" end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:PermRanks() return nil end
function ns.DB:PermDef() return {} end
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return settings end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
local function m(full, main, addon) return { full = full, short = full, classFile = "MAGE", main = main, hasAddon = addon } end
ns.Roster = { members = {
  m("Marc Priest", nil, true), m("Marc Druid", "Marc Priest", true),
  m("Probably Shawn", nil, true), m("Grud Sama", nil, true), m("No Addon", nil, false) } }
ns.Roster.byName = {}
for _, e in ipairs(ns.Roster.members) do ns.Roster.byName[e.full] = e end
C_Timer = { After = function() end, NewTicker = function() end }
GetTime = function() return 1 end
date, time = os.date, os.time
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
assert(loadfile(ROOT .. "/Services/Sharing.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/HallOfFame.lua"))("NGM", ns)
local HF = ns.HallOfFame

-- Social Butterfly
local t0 = 1800000000 - (1800000000 % 86400) -- midnight UTC
for i = 1, 10 do HF:SocialNote(true, t0 + i) end      -- talking to yourself
assert(HF:SocialTotal() == 0, "no one else spoke")
HF:SocialNote(false, t0 + 20)                           -- someone answers
assert(HF:SocialTotal() == 1)
for i = 1, 10 do HF:SocialNote(true, t0 + 30 + i); HF:SocialNote(false, t0 + 50 + i) end
assert(HF:SocialTotal() == 1, "a chatty block counts once")
for b = 1, 20 do HF:SocialNote(false, t0 + b * 900); HF:SocialNote(true, t0 + b * 900 + 1) end
assert(HF:SocialTotal() == 8, "8 blocks a day at most: " .. HF:SocialTotal())
HF:SocialNote(true, t0 + 86400 + 5); HF:SocialNote(false, t0 + 86400 + 6)
assert(HF:SocialTotal() == 9, "the next day counts again")
assert(HF.Format(HF.BY_KEY.social, 9) == "2.2 h" or HF.Format(HF.BY_KEY.social, 9) == "2.3 h")
assert(HF.Format(HF.BY_KEY.quests, 12345) == "12,345")

-- last month's numbers from guildmates (records written last month)
local month = 202612
HF.Month = function(t) if t then return tonumber(os.date("!%Y%m", t)) end return month end
local function put(full, this, all, m)
  guild.sync.guild["HF:" .. full] = { v = HF.Encode(m or 202611, all or this, this, 0, {}), t = 1, a = full }
end
put("Marc Priest", { quests = 40, kills = 100 })
put("Marc Druid", { quests = 20, deaths = 3 })          -- added to Marc's 40
put("Probably Shawn", { quests = 60, kills = 100, deaths = 9 })
put("Grud Sama", { kills = 50, deaths = 9 })
local champs = HF:Champions(month)
local function keys(c) local t = {} for _, p in ipairs(c.winners) do t[#t + 1] = p.key end table.sort(t) return table.concat(t, ",") end
assert(keys(champs.quests) == "Marc Priest,Probably Shawn" and champs.quests.n == 60, "alts added up; a tie shares the title")
assert(keys(champs.kills) == "Marc Priest,Probably Shawn")
assert(keys(champs.deaths) == "Grud Sama,Probably Shawn")
assert(not champs.hugs and not champs.champs, "no title without numbers, none for the wins card itself")
local b = HF:Boards("last", month)
assert(#b.boards.quests == 2 and b.boards.quests[1].n == 60, "Marc listed once (main + alt)")

-- crowning schedule: 00:00 UTC on the 2nd
assert(HF.UTCDay(2026, 12, 1) == 1796083200 and HF.UTCDay(2027, 3, 1) == 1803859200)
assert(HF.CrownTime(202612) == 1796083200 + 86400)
assert(HF.CrownTime(202603) == HF.UTCDay(2026, 3, 2), "leap-year-safe")
local st = HF:CrownStatus(1796083200 + 3600) -- 1 Dec, 01:00 UTC
assert(st.state == "tallying" and st.won == 202611 and st.at == 1796083200 + 86400, st.state)
st = HF:CrownStatus(1796083200 + 86400 + 60) -- the 2nd, no officer yet
assert(st.state == "due", st.state)
assert(HF:RecordedChampions(month) == nil, "nothing official before they're recorded")

-- titles are recorded by officers only, from the 2nd of the month
local dec1, dec5 = 1796083200 + 3600, 1796083200 + 4 * 86400 -- 1 and 5 Dec 2026 UTC
assert(os.date("!%Y%m%d", dec1) == "20261201")
assert(not HF:RecordChampions(dec5), "not an officer")
iAmOfficer = true
assert(not HF:RecordChampions(dec1), "the 1st: numbers still being tallied")
-- a guild using NGM Peon: NGM Peon crowns them, so no officer's game does
local realValue = ns.Sync.Value
ns.Sync.Value = function(self, k) if k == "GS:peon" then return "1" end return realValue(self, k) end
assert(HF:PeonCrowns() and not HF:RecordChampions(dec1 + 86400), "NGM Peon crowns: the addon doesn't")
ns.Sync.Value = realValue
local printed = {}
ns.Print = function(_, m) printed[#printed + 1] = m end
assert(HF:RecordChampions(dec1 + 86400), "the 2nd")
assert(#printed == 1 and printed[1]:find("November's Hall of Fame champions have been crowned", 1, true)
  and printed[1]:find("Announce Champions", 1, true), "the officer who crowned them is told")
assert(guild.sync.guild["HW:202611"].v == "quests=Marc Priest,Probably Shawn;kills=Marc Priest,Probably Shawn;deaths=Grud Sama,Probably Shawn",
  guild.sync.guild["HW:202611"].v)
assert(not HF:RecordChampions(dec5), "written once")
-- recount (until 00:00 UTC on the 3rd): late numbers can change a winner
local dec2 = 1796083200 + 86400
printed = {}
put("Grud Sama", { quests = 80, kills = 50, deaths = 9 })      -- Grud's late numbers arrive
assert(not HF:RecordChampions(dec5), "after the recount day nothing changes")
assert(HF:RecordChampions(dec2 + 3600), "recount on the 2nd")
local champsNow = HF.DecodeChampions(guild.sync.guild["HW:202611"].v)
assert(#champsNow.quests == 1 and champsNow.quests[1] == "Grud Sama", "Grud takes Quests")
assert(champsNow.kills[1] == "Marc Priest" and #champsNow.deaths == 2, "other titles untouched")
assert(#printed == 1 and printed[1]:find("Recount:", 1, true) and printed[1]:find("Quests completed: Grud Sama (was Marc Priest & Probably Shawn)", 1, true), printed[1])
-- an officer whose copy is missing Grud's numbers can't undo it
local saved = guild.sync.guild["HF:Grud Sama"]
guild.sync.guild["HF:Grud Sama"] = nil
assert(not HF:RecordChampions(dec2 + 7200), "missing numbers never undo a correction")
assert(HF.DecodeChampions(guild.sync.guild["HW:202611"].v).quests[1] == "Grud Sama")
guild.sync.guild["HF:Grud Sama"] = saved
-- put things back for the checks below (Grud's earlier numbers, original champions)
put("Grud Sama", { kills = 50, deaths = 9 })
guild.sync.guild["HW:202611"].v = "quests=Marc Priest,Probably Shawn;kills=Marc Priest,Probably Shawn;deaths=Grud Sama,Probably Shawn"

st = HF:CrownStatus(dec5)
assert(st.state == "crowned" and st.nextWon == 202612 and st.nextAt == HF.CrownTime(202701))
local rc = HF:RecordedChampions(month)
assert(rc.quests.n == 60 and #rc.quests.winners == 2 and rc.deaths.n == 9, "recorded champions with their numbers")
local wins = HF:Wins("all", month)
assert(wins["Marc Priest"] == 2 and wins["Probably Shawn"] == 3 and wins["Grud Sama"] == 1)
assert(HF:Wins("month", month)["Probably Shawn"] == 3, "this month's titles = last month's champions")
assert(not next(HF:Wins("last", month)))
b = HF:Boards("all", month)
assert(b.boards.champs[1].key == "Probably Shawn" and b.boards.champs[1].n == 3)

-- titles held this month, shown in tooltips and on profiles
local titles, won = HF:TitlesFor("Marc Druid", month) -- an alt shows their person's titles
assert(won == 202611 and #titles == 2 and titles[1] == "Quests completed" and titles[2] == "Kills")
assert(HF:TitleText("Grud Sama"):find("November's Champion:|r Deaths", 1, true))
assert(HF:TitleText("No Addon") == nil)
assert(#HF:TitlesFor("Marc Priest", 202701) == 0, "a month later the titles are gone")

-- announcing them: lines under 255, who announced last
local lines = HF:AnnounceLines(202611)
assert(lines and #lines == 1 and lines[1]:find("^Congrats to November's Hall of Fame champions! Quests completed: Marc Priest & Probably Shawn;"), lines[1])
for _, l in ipairs(lines) do assert(#l <= 255) end
local said = {}
SendChatMessage = function(msg, chan) said[#said + 1] = chan .. ":" .. msg end
assert(HF:Announce())
assert(#said == 1 and said[1]:find("^GUILD:Congrats"))
local at, by = HF:LastAnnounced(202611)
assert(at == NOW and by == "Marc Priest")
assert(HF:Announce() and #said == 2, "officers can announce again (not greyed out)")
-- Shawn announced; then a recount by Marc changed them: every officer sees it
guild.sync.guild["HA:202611"] = { v = tostring(NOW - 3600), t = NOW - 3600, a = "Probably Shawn" }
local hw = guild.sync.guild["HW:202611"]
local savedT, savedA = hw.t, hw.a
hw.t, hw.a = NOW - 60, "Marc Priest"
local status = HF:AnnounceStatus(202611)
assert(status.text:find("Corrected", 1, true) and status.text:find("by Marc Priest, AFTER Probably Shawn last announced", 1, true), status.text)
hw.t, hw.a = NOW - 7200, savedA
assert(HF:AnnounceStatus(202611).text:find("^Last announced .- by Probably Shawn%.$"), "crowned before the announcement: no correction")
hw.t = savedT
-- many winners: split into several lines, each under 255
local many = {}
for _, st in ipairs(HF.STATS) do if not st.noChampion then many[st.key] = { winners = {
  { key = "Abcdefghijkl Abcdefghijkl" }, { key = "Bbcdefghijkl Abcdefghijkl" } } } end end
guild.sync.guild["HW:202610"] = { v = HF.EncodeChampions(many), t = 1, a = "Marc Priest" }
ns.Roster.byName["Abcdefghijkl Abcdefghijkl"] = { full = "Abcdefghijkl Abcdefghijkl", short = "Abcdefghijkl Abcdefghijkl" }
ns.Roster.byName["Bbcdefghijkl Abcdefghijkl"] = { full = "Bbcdefghijkl Abcdefghijkl", short = "Bbcdefghijkl Abcdefghijkl" }
lines = HF:AnnounceLines(202610)
assert(#lines > 1)
for _, l in ipairs(lines) do assert(#l <= 255, #l) end
-- names that aren't guildmates never reach guild chat
guild.sync.guild["HW:202610"].v = "quests=Visit my site,Marc Priest"
lines = HF:AnnounceLines(202610)
assert(#lines == 1 and not lines[1]:find("Visit", 1, true) and lines[1]:find("Quests completed: Marc Priest", 1, true))
guild.sync.guild["HW:202610"] = nil

-- a member can't award themselves titles: champs in their own record is ignored
put("Grud Sama", { kills = 50, deaths = 9 }, { kills = 50, deaths = 9, champs = 99 })
assert(not HF.Decode(guild.sync.guild["HF:Grud Sama"].v).all.champs)
assert(HF:Boards("all", month).boards.champs[3].n == 1)
-- nor send titles as a non-officer: refused by the sync
iAmOfficer = false
ns.Sync:OnMessage(table.concat({ ns.Sync.PROTO, "R", "HW:202610", "1", "Grud Sama", "", "quests=Grud Sama" }, "\t"), "GUILD", "Grud Sama")
assert(not guild.sync.guild["HW:202610"], "only officers write champion titles")

-- plausibility: absurd numbers leave the whole person out
put("Grud Sama", { kills = 50 }, { kills = 50, quests = 999999 })
b = HF:Boards("all", month)
assert(b.flagged == 1)
for _, p in ipairs(b.boards.kills) do assert(p.key ~= "Grud Sama", "flagged member listed") end
put("Grud Sama", { quests = 31 * 150 + 1 }, { quests = 99999 })
assert(HF:Implausible("Grud Sama"), "a month over 31 days of play")
put("Grud Sama", { quests = 10 }, { quests = 5 })
assert(HF:Implausible("Grud Sama"), "a month bigger than all time")
put("Grud Sama", { social = 9 }, { social = 9 })
assert(not HF:Implausible("Grud Sama"))
put("Grud Sama", { kills = 50 }, { kills = 50 })
assert(not HF:Implausible("Grud Sama"))

-- officers can leave someone out
guild.sync.guild["HX:Probably Shawn"] = { v = "1", t = 1, a = "Marc Priest" }
b = HF:Boards("all", month)
assert(b.hidden == 1)
for _, p in ipairs(b.boards.champs) do assert(p.key ~= "Probably Shawn") end
print("OK")
