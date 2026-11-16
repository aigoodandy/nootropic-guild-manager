-- Test: sync (protocol 6) in a small simulated guild (tests/sim.lua): checks
-- at login, fetching exactly what's missing from the right person, nothing
-- sent while nothing changes, officers known by rank (and no longer after a
-- demotion), a member whose guild channel delivers nothing, and what isn't
-- read at all.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local Sim = dofile(ROOT .. "/tests/sim.lua")(ROOT)
local function check(name, ok) print(("%-66s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end

local g = Sim.Guild({
  { "Gm Boss", 0, "Guild Master" }, { "Ola Officer", 1, "Officer" },
  { "Ann Member", 3, "Member" }, { "Bob Member", 3, "Member" }, { "Cat Member", 3, "Member" },
  { "Myk Broken", 3, "Member" }, { "Old Copy", 3, "Member" },
})
local T0 = g:Now() - 86400
local function R(v, t, a) return { v = v, t = t, a = a } end
-- what everyone's copies already agree on
local function Seed(c)
  for _, n in ipairs({ "Gm Boss", "Ola Officer", "Ann Member", "Bob Member", "Cat Member", "Myk Broken" }) do
    c.store["AV:" .. n] = R("2.12.0", T0, n)
    c.store["P:" .. n] = R("Holy;;Alchemy:150", T0, n)
    c.store["HF:" .. n] = R(string.rep("1,", 40), T0, n)
  end
  c.store["M:Cat Member"] = R("", T0, "Ola Officer")
  c.store["GS:officers"] = R("Officer", T0, "Gm Boss")
end
local GM, OLA, ANN, BOB = g:Client("Gm Boss"), g:Client("Ola Officer"), g:Client("Ann Member"), g:Client("Bob Member")
for _, c in ipairs({ GM, OLA, ANN, BOB }) do Seed(c) end

------------------------------------------------------------------------
-- 1. logging in with nothing to catch up on: a handful of tiny messages
------------------------------------------------------------------------
g:Login("Gm Boss") g:Login("Ola Officer") g:Login("Ann Member")
g:Settle()
g:ResetStats()
g:Login("Bob Member")
local took = g:Settle()
check(("Bob's login, all in sync: %d messages, %d bytes"):format(g.stats.messages, g.stats.bytes), g.stats.messages <= 8 and g.stats.bytes < 600)
check("no records were sent for it", not g.stats.byKind.R and not g.stats.byKind.B and not g.stats.byKind.E)
check("Bob's copy says it's in sync", BOB.S:Health() == "ok")

------------------------------------------------------------------------
-- 2. nothing changes: nothing is sent
------------------------------------------------------------------------
g:ResetStats()
g:Run(3 * 3600)
check("three quiet hours: no messages at all", g.stats.messages == 0)

------------------------------------------------------------------------
-- 3. a change is sent once, and everyone online gets it
------------------------------------------------------------------------
g:ResetStats()
g:As(ANN, function() ANN.S:Set("P:Ann Member", "Shadow;;Alchemy:160") end)
g:Settle()
check("one change, one message (" .. g.stats.messages .. ")", g.stats.messages == 1)
check("everyone online has it", BOB.store["P:Ann Member"].v == "Shadow;;Alchemy:160" and GM.store["P:Ann Member"].v == "Shadow;;Alchemy:160")

------------------------------------------------------------------------
-- 4. catching up: exactly what's missing, from the right person
------------------------------------------------------------------------
g:Logout("Bob Member")
g:As(ANN, function() ANN.S:Set("SC:Ann Member", string.rep("f", 42)) end)          -- Ann (online) changes
g:As(OLA, function() OLA.S:Set("M:Bob Member", "") end)                              -- an officer edits
OLA.store["P:Cat Member"] = R("Frost;;", g:Now(), "Cat Member")                       -- Cat (offline) changed; Ola has it
GM.store["P:Cat Member"] = R("Frost;;", g:Now(), "Cat Member")
ANN.store["P:Cat Member"] = R("Frost;;", g:Now(), "Cat Member")
g:Settle()
g:ResetStats()
g:Login("Bob Member")
g:Settle()
check("Bob got Ann's change while he was away", BOB.store["SC:Ann Member"] ~= nil)
check("and the officer's edit", BOB.store["M:Bob Member"] ~= nil)
check("and offline Cat's change (from an officer)", BOB.store["P:Cat Member"] and BOB.store["P:Cat Member"].v == "Frost;;")
check(("only the 3 missing records went out (%d R, %d bundles)"):format(g.stats.byKind.R or 0, g.stats.byKind.B or 0),
  (g.stats.byKind.R or 0) + (g.stats.byKind.B or 0) <= 3)
check("in sync afterwards", BOB.S:Health() == "ok")

------------------------------------------------------------------------
-- 5. a regular member never hands out someone else's records
------------------------------------------------------------------------
g:Logout("Gm Boss") g:Logout("Ola Officer") g:Logout("Bob Member")
ANN.store["P:Cat Member"] = R("Fire;;", g:Now() + 1, "Cat Member")
g:Login("Bob Member")
g:Settle()
check("with no officer online, Cat's newer record doesn't spread from Ann", BOB.store["P:Cat Member"].v == "Frost;;")

------------------------------------------------------------------------
-- 6. officers by rank: learned by the Guild Master's copy, lost on demotion
------------------------------------------------------------------------
GM.store["GS:officers"] = nil
for _, c in ipairs({ OLA, ANN, BOB }) do c.store["GS:officers"] = nil end
g:Login("Gm Boss") g:Login("Ola Officer")
g:Settle()
check("the Guild Master's copy names the officer rank", GM.S:Value("GS:officers") == "Officer")
check("members trust Ola without seeing the officer channel", BOB.S:KnownOfficer("Ola Officer") and ANN.S:KnownOfficer("Ola Officer"))
check("but not Ann", not BOB.S:KnownOfficer("Ann Member"))
g.byName["Ola Officer"].rankIndex, g.byName["Ola Officer"].rank = 3, "Member"
check("demoted: nobody trusts Ola any more, the Guild Master included", not BOB.S:KnownOfficer("Ola Officer") and not GM.S:KnownOfficer("Ola Officer"))
g.byName["Ola Officer"].rankIndex, g.byName["Ola Officer"].rank = 1, "Officer"
-- a rank the guild no longer has is dropped
g.ranks[2].name = "Captain"
g.byName["Ola Officer"].rank = "Captain"
g:As(GM, function() GM.S:NoteOfficer("Ola Officer") end)
g:Settle()
check("a renamed officer rank is replaced", GM.S:Value("GS:officers") == "Captain" and BOB.S:Value("GS:officers") == "Captain")
-- only the Guild Master may name officer ranks
g:As(BOB, function()
  BOB.S:OnMessage(table.concat({ "6", "R", "GS:officers", tostring(g:Now() + 5), "Ann Member", "", "Member" }, "\t"), "GUILD", "Ann Member")
end)
check("a member can't name officer ranks", BOB.S:Value("GS:officers") == "Captain")

-- the game's own rank settings: read where the game allows, and written
-- down by the Guild Master's copy for the rest (here only the Guild
-- Master's copy may read them)
C_GuildInfo = {}
g.ranks = { { index = 0, name = "Guild Master" }, { index = 1, name = "Captain" }, { index = 3, name = "Member" } }
-- by rank index, as WoW: Forever reports them: 5 Promote, 7 Invite Member,
-- 15 Guild Bank Repair, 21 Recruitment, 22 Is Officer (Member here: like a
-- Raid Leader, Invite without Promote; the GM's ranks in game, 2026-11-16)
local FLAGS = { [1] = { [22] = true, [5] = true, [7] = true }, [3] = { [7] = true, [15] = true, [21] = true } }
C_GuildInfo.GuildControlGetRankFlags = function(order)
  local c = g:Current()
  if not c or c.entry.rankIndex ~= 0 then return { false, false } end -- others: all off (not told)
  local t = {}
  for k, v in pairs(FLAGS[order - 1] or {}) do t[k] = v end
  t[1] = true -- guild chat: a rank always has some setting
  return t
end
for _, c in ipairs({ GM, OLA, ANN, BOB }) do c.S.flagCache = {} end
g:As(GM, function() GM.S:PublishRanks() end)
g:Settle()
check("the Guild Master's copy writes down the game's officer ranks", GM.S:Value("GS:officers") == "Captain" and BOB.S:Value("GS:officers") == "Captain")
check("and its recruiting ranks", BOB.S:Value("GS:recruiters") == "Captain;Member")
check("members use them: Ann may recruit, Ola is an officer", BOB.S:MayRecruitName("Ann Member") and BOB.S:KnownOfficer("Ola Officer"))
FLAGS[3] = { [5] = true } -- Promote alone isn't Invite
for _, c in ipairs({ GM, OLA, ANN, BOB }) do c.S.flagCache = {} end
g:As(GM, function() GM.S:PublishRanks() end)
g:Settle()
check("taking Invite away from a rank in the game updates everyone", not BOB.S:MayRecruitName("Ann Member"))
C_GuildInfo = nil
for _, c in ipairs({ GM, OLA, ANN, BOB }) do c.S.flagCache = {} end

------------------------------------------------------------------------
-- 7. a guild channel that delivers nothing: through one officer
------------------------------------------------------------------------
local MYK = g:Client("Myk Broken", { broken = true })
Seed(MYK)
MYK.store["P:Myk Broken"] = R("Arcane;;Tailoring:90", g:Now(), "Myk Broken")
MYK.store["AV:Myk Broken"] = R("2.11.0", T0, "Myk Broken")
for _, c in ipairs({ GM, OLA, ANN, BOB }) do c.store["AV:Myk Broken"] = R("2.11.0", T0, "Myk Broken") end
g:ResetStats()
g:Login("Myk Broken")
g:Settle()
check("her copy noticed and picked an officer", MYK.S.relay ~= nil and MYK.S.relayAcked)
check("everyone has her new version", ANN.store["AV:Myk Broken"].v == "2.12.0" and BOB.store["AV:Myk Broken"].v == "2.12.0")
check("and her changed record", ANN.store["P:Myk Broken"].v == "Arcane;;Tailoring:90" and GM.store["P:Myk Broken"].v == "Arcane;;Tailoring:90")
check(("whispers stayed few (%d)"):format(g.stats.byChannel.WHISPER or 0), (g.stats.byChannel.WHISPER or 0) <= 12)
check("her status says so", MYK.S:Health() == "busy" and select(2, MYK.S:Health()):find(MYK.S.relay, 1, true))
-- her later changes go the same way
g:As(MYK, function() MYK.S:Set("SC:Myk Broken", string.rep("0", 42)) end)
g:Settle()
check("her next change reaches everyone too", BOB.store["SC:Myk Broken"] ~= nil)
-- the officer passes on only what she wrote
local relay = g.clients[MYK.S.relay]
g:As(relay, function()
  relay.S:OnMessage(table.concat({ "6", "R", "P:Bob Member", tostring(g:Now() + 9), "Bob Member", "", "forged" }, "\t"), "WHISPER", "Myk Broken")
end)
g:Settle()
check("a record she didn't write isn't kept or passed on", relay.store["P:Bob Member"].v ~= "forged" and ANN.store["P:Bob Member"].v ~= "forged")

------------------------------------------------------------------------
-- 8. what isn't read at all
------------------------------------------------------------------------
local function poke(c, channel, from)
  g:As(c, function()
    c.S:OnMessage(table.concat({ "6", "R", "P:" .. from, tostring(g:Now() + 30), from, "", channel }, "\t"), channel, from)
  end)
end
poke(BOB, "PARTY", "Ann Member")
check("party messages", BOB.store["P:Ann Member"].v ~= "PARTY")
poke(BOB, "WHISPER", "Ann Member")
check("whispers to a regular member", BOB.store["P:Ann Member"].v ~= "WHISPER")
poke(GM, "WHISPER", "Stranger Danger")
check("whispers from outside the guild, even to an officer", GM.store["P:Stranger Danger"] == nil)
g:As(GM, function()
  for i = 1, 200 do GM.S:OnMessage(table.concat({ "6", "R", "AV:Ann Member", tostring(g:Now() + 40 + i), "Ann Member", "", "v" .. i }, "\t"), "WHISPER", "Ann Member") end
end)
check("more than 120 whispers a minute from one guildmate", GM.store["AV:Ann Member"].v == "v120")

------------------------------------------------------------------------
-- 9. older copies: only their version is read
------------------------------------------------------------------------
local OLD = g:Client("Old Copy")
g:As(BOB, function()
  BOB.S:OnMessage(table.concat({ "5", "R", "AV:Old Copy", tostring(g:Now()), "Old Copy", "", "2.11.0" }, "\t"), "GUILD", "Old Copy")
  BOB.S:OnMessage(table.concat({ "5", "R", "P:Old Copy", tostring(g:Now()), "Old Copy", "", "x" }, "\t"), "GUILD", "Old Copy")
  BOB.S:OnMessage(table.concat({ "5", "D", "guild", "1,2,3" }, "\t"), "GUILD", "Old Copy")
end)
check("an older copy's version shows", BOB.store["AV:Old Copy"] and BOB.store["AV:Old Copy"].v == "2.11.0")
check("nothing else of theirs is read", BOB.store["P:Old Copy"] == nil)
print("OK")
