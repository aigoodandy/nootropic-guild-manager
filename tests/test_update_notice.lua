-- New version notice: at login, when a guildmate's newer version arrives,
-- and every hour while behind. Only released versions count: a test build
-- ("3.0.2-test1") or "dev" never makes the guild think an update is out.
local ROOT = arg[1]
local ns = { version = "3.0.1", GOLD = "|cffffd100" }
local printed = {}
function ns:Print(m) printed[#printed + 1] = m end
function ns:On() end
function ns:RegisterEvent() end
function ns:Fire() end
function ns.Debounce(_, _, fn) fn() end
assert(loadfile(ROOT .. "/Core/Core.lua") and true)
-- the real version comparison, without the rest of Core.lua
local core = assert(io.open(ROOT .. "/Core/Core.lua")):read("*a")
local cmp = core:match("(local function ParseVersion.-\nfunction ns%.CompareVersions.-\nend)")
assert(cmp, "CompareVersions not found")
assert(load(cmp, "cmp", "t", setmetatable({ ns = ns }, { __index = _G })))()
local guild = { members = {} }
ns.DB = { Guild = function() return guild end }
local timers, ticker = {}, nil
C_Timer = { After = function(s, fn) timers[#timers + 1] = { s, fn } end, NewTicker = function(s, fn) ticker = { s, fn }; return {} end }
assert(loadfile(ROOT .. "/Services/Roster.lua"))("NGM", ns)
local R = ns.Roster

-- nobody newer: nothing
guild.members["Ann"] = { version = "3.0.1" }
assert(R:CheckVersion() == false and #printed == 0)
-- a test build and a dev copy don't count
guild.members["Tester"] = { version = "3.0.2-test1" }
guild.members["Dev"] = { version = "dev" }
assert(R:CheckVersion() == false and #printed == 0, "test builds are not releases")
-- a real release: told once
guild.members["Bob"] = { version = "3.0.2" }
assert(R:CheckVersion() == true and #printed == 1)
assert(printed[1]:find("NGM 3.0.2 is out") and printed[1]:find("you have 3.0.1") and printed[1]:find("ngmpeon.app"), printed[1])
assert(R:CheckVersion() == false and #printed == 1, "once per version, not every sync")
-- the hourly reminder repeats it
assert(R:CheckVersion(true) == true and #printed == 2)
-- an even newer release: told again
guild.members["Cy"] = { version = "3.1.0" }
assert(R:CheckVersion() == true and printed[3]:find("NGM 3.1.0 is out"))
-- started at login: a check shortly after, and an hourly ticker
R:StartVersionCheck()
assert(#timers == 1 and timers[1][1] == 15 and ticker and ticker[1] == 3600)
R:StartVersionCheck()
assert(#timers == 1, "started once")

-- NGM Peon's word on the newest release (/ngm peon) counts too
guild.peon = { release = "3.2.0" }
assert(R:NewestVersion() == "3.2.0" and R:CheckVersion() == true and printed[#printed]:find("NGM 3.2.0 is out"))
guild.peon = { release = "4.0.0-test1" }
assert(R:NewestVersion() == "3.1.0", "a test build from anywhere doesn't count")
guild.peon = nil

-- your party or raid, outside the guild too
local sent, events, now, group = {}, {}, 1000, "PARTY"
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(p, m, c) sent[#sent + 1] = { p, m, c } end }
function ns:RegisterEvent(e, fn) events[e] = fn end
function GetTime() return now end
function IsInRaid() return group == "RAID" end
function IsInGroup() return group ~= nil end
function GetNumGroupMembers() return 2 end
ns.NormalizeName = function(n) return n end
ns.PlayerFullName = function() return "Me" end
ns.version = "3.0.1"
R.toldNewer = nil
R:StartGroupVersion()
assert(events.CHAT_MSG_ADDON and events.GROUP_ROSTER_UPDATE, "listening")
-- joining a group: you say your version (released copies only, once a minute)
events.GROUP_ROSTER_UPDATE()
assert(#sent == 1 and sent[1][1] == "NGMVer" and sent[1][2] == "V\t3.0.1" and sent[1][3] == "PARTY")
assert(R:SayVersion() == false, "once a minute")
ns.version = "3.0.2-test1"; now = now + 61
assert(R:SayVersion() == false, "test builds don't say")
ns.version = "3.0.1"
-- hearing a newer release from the group: told
local n = #printed
events.CHAT_MSG_ADDON(nil, "NGMVer", "V\t3.5.0", "PARTY", "Stranger")
assert(R.heard["3.5.0"] and #printed == n + 1 and printed[#printed]:find("NGM 3.5.0 is out"))
-- odd, test-build, whispered and your own messages are ignored
events.CHAT_MSG_ADDON(nil, "NGMVer", "V\t9.0.0-beta", "PARTY", "Stranger")
events.CHAT_MSG_ADDON(nil, "NGMVer", "V\t9.0.0", "WHISPER", "Stranger")
events.CHAT_MSG_ADDON(nil, "NGMVer", "V\t9.0.0", "RAID", "Me")
events.CHAT_MSG_ADDON(nil, "NotOurs", "V\t9.0.0", "RAID", "Stranger")
assert(not R.heard["9.0.0"] and not R.heard["9.0.0-beta"] and R:NewestVersion() == "3.5.0")
-- someone behind you: answered so they learn it too
group = "RAID"; ns.version = "3.6.0"
events.CHAT_MSG_ADDON(nil, "NGMVer", "V\t3.0.0", "RAID", "Old Timer")
assert(#sent == 2 and sent[2][2] == "V\t3.6.0" and sent[2][3] == "RAID")
-- not in a group: nothing to say
group = nil; now = now + 61
assert(R:SayVersion() == false)
print("OK")
