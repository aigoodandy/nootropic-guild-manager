-- Who sees which tab: Recruitment follows the game's Invite Member setting
-- (a Recruiter rank with Invite but not Officer sees it); Audit is officers
-- only; the rest are for everyone. (A Recruiter couldn't see Recruitment in
-- 3.0.0: the tab still asked a removed addon permission.)
local ROOT = arg[1]
local src = assert(io.open(ROOT .. "/UI/MainFrame.lua")):read("*a")
local body = src:match("function UI:IsTabAvailable%(id%)(.-)\nend")
assert(body, "IsTabAvailable not found")
local UI = { TAB_RECRUIT = 3 }
local officer, invite = false, false
local ns = { IsOfficer = function() return officer end, Recruit = { MayRecruit = function() return invite end },
  DB = { HasPerm = function() error("tabs must not ask addon permissions") end } }
local OFFICER_TABS = { [4] = true }
local f = assert(load("local UI, ns, OFFICER_TABS = ...; return function(self, id)" .. body .. "\nend"))(UI, ns, OFFICER_TABS)
local function sees(id) return f(UI, id) and true or false end
-- a Recruiter: Invite Member, not Officer
invite, officer = true, false
assert(sees(3), "a rank with Invite Member sees Recruitment")
assert(not sees(4), "but not Audit")
assert(sees(1) and sees(2) and sees(5) and sees(6) and sees(7), "and every other tab")
-- a member: neither
invite, officer = false, false
assert(not sees(3) and not sees(4), "a member sees neither")
-- an officer without Invite Member
invite, officer = false, true
assert(not sees(3) and sees(4), "an officer without Invite sees Audit, not Recruitment")
print("OK")
