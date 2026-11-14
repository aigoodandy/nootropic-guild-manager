-- Test: Recipes: capturing learned recipes from your own profession window, filtered windows, dropped professions, searching. Raid readiness checks.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end function ns:Print(m) print("  [print] " .. m) end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return fn end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.IsOfficer() return false end
function ns.PlayerFullName() return "Me Self-R" end
function ns.NormalizeName(n) return n end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
local settings = {}
ns.DB = { PERM_BY_TYPE = {}, Guild = function() return guild end, Now = function() return NOW end,
  Settings = function() return settings end, EnsureMember = function(_, f) guild.members[f] = guild.members[f] or {} return guild.members[f] end,
  HasPerm = function() return true end, PermRanks = function() end, PermDef = function() return {} end }
ns.Roster = { byName = { ["Me Self-R"] = { rankIndex = 4, online = true }, ["Ann Smith-R"] = { rankIndex = 4, online = false }, ["Bo Online-R"] = { rankIndex = 4, online = true } } }
local profs = { { name = "Alchemy" } }
ns.Comm = { Snapshot = function() return { profs = profs } end }
C_Timer = { After = function() end }
GetTime = function() return 1 end
IsInGuild = function() return true end
ns.Data = {}
assert(loadfile(ROOT .. "/Core/Data.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
assert(loadfile(ROOT .. "/Services/Recipes.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Readiness.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Sharing.lua"))("NGM", ns)
local reports = 0
ns.Comm.Report = function() reports = reports + 1 end
local RCP, RD = ns.Recipes, ns.Readiness
local names = { [2330] = "Minor Healing Potion", [3170] = "Weak Troll's Blood Elixir", [7836] = "Blackmouth Oil", [17635] = "Flask of the Titans" }
C_Spell = { GetSpellName = function(id) return names[id] end }
local visible = { 2330, 3170, 7836 }
local learned = { [2330] = true, [3170] = true }
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy" } end,
  GetFilteredRecipeIDs = function() return visible end,
  GetRecipeInfo = function(id) return { recipeID = id, learned = learned[id] or false } end,
  IsRecipeInSkillLine = function() return true end,
  IsNPCCrafting = function() return false end,
}
RCP:Capture()
local key = "RP:Me Self-R:171"
print("shared:", guild.sync.guild[key].v)
local _, ids = RCP.Decode(guild.sync.guild[key].v); assert(ids[2330] and ids[3170] and not ids[7836], "unlearned shared")
visible = { 7836 }; learned[7836] = true; RCP:Capture()          -- a search filter hides the others
_, ids = RCP.Decode(guild.sync.guild[key].v); assert(ids[2330] and ids[7836], "filtered capture dropped recipes")
C_TradeSkillUI.IsNPCCrafting = function() return true end; visible = { 17635 }; learned[17635] = true; RCP:Capture()
_, ids = RCP.Decode(guild.sync.guild[key].v); assert(not ids[17635], "NPC crafting captured"); C_TradeSkillUI.IsNPCCrafting = function() return false end
-- other members' lists arrive
guild.sync.guild["RP:Ann Smith-R:171"] = { v = RCP.Encode("Alchemy", { [2330] = true, [17635] = true }), t = 1, a = "Ann Smith-R" }
guild.sync.guild["RP:Bo Online-R:171"] = { v = RCP.Encode("Alchemy", { [2330] = true }), t = 1, a = "Bo Online-R" }
guild.sync.guild["RP:Gone Left-R:171"] = { v = RCP.Encode("Alchemy", { [2330] = true }), t = 1, a = "Gone Left-R" }
local res = RCP:Search("healing")
print("search healing:", res[1].name, table.concat(res[1].crafters, ", "))
assert(#res == 1 and res[1].crafters[1] ~= "Ann Smith-R" and #res[1].crafters == 3, "online first / ex-member excluded")
assert(#RCP:Search("flask") == 1 and RCP:Search("flask")[1].crafters[1] == "Ann Smith-R")
assert(RCP:Count("Me Self-R") == 3)
profs = { { name = "Herbalism" } }; RCP:Prune()
assert(guild.sync.guild[key].v == "", "dropped profession not cleared"); print("pruned after dropping Alchemy")
-- readiness
local quests, items = {}, {}
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return quests[id] or false end }
C_Item = { GetItemCount = function(id) return items[id] or 0 end }
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end, GetContainerItemInfo = function() return nil end }
RD:Publish(); print("readiness none:", guild.sync.guild["RR:Me Self-R"].v); assert(next(RD:For("Me Self-R")) == nil)
quests[6602] = true; RD:Publish(); assert(RD:For("Me Self-R").ony)
C_Container.GetContainerItemInfo = function() return { hyperlink = "|cff0070dd|Hitem:999001::|h[Brooch of the Wardens]|h|r", itemID = 999001 } end
RD:Publish(); assert(RD:For("Me Self-R").brooch and settings.knownItemIds["Brooch of the Wardens"] == 999001)
C_Container.GetContainerItemInfo = function() return nil end; items[999001] = 1; RD:Publish(); assert(RD:For("Me Self-R").brooch, "known ID in bank")
print("readiness:", guild.sync.guild["RR:Me Self-R"].v, " unknown member:", tostring(RD:For("Ann Smith-R")))
-- sharing switches
local SH = ns.Sharing
profs = { { name = "Alchemy" } }; visible = { 2330 }; RCP:Capture()
assert(guild.sync.guild[key].v ~= "", "recipes not shared again")
SH:Set("recipes", false)
assert(guild.sync.guild[key].v == "", "recipes not cleared when sharing turned off")
RCP:Capture(); assert(guild.sync.guild[key].v == "", "captured while sharing is off")
-- spec, professions and Play Together are public: no switch, always shared
guild.sync.guild["P:Me Self-R"] = { v = "Holy;;", t = 1, a = "Me Self-R" }
SH:Set("report", false); assert(SH:Get("report") and guild.sync.guild["P:Me Self-R"].v ~= "", "no switch for spec and professions")
SH:Set("together", false); assert(SH:Get("together"), "no switch for Play Together")
print("sharing switches: ok")
print("OK")
