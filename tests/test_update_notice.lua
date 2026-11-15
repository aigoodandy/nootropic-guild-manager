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
print("OK")
