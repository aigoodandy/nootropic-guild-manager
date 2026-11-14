-- Test: NGM Peon setup code: the addon makes exactly the code NGM Peon expects (reference codes from ngm-hub's formatSetupCode), and only for the Guild Master.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
ns.GOLD, ns.ORANGE, ns.BLUE = "|cfffabd2f", "|cfffe8019", "|cff83a598" -- Core.lua sets these
assert(loadfile(ROOT .. "/Services/DiscordCode.lua"))("NGM", ns)
local DC = ns.DiscordCode

-- the same inputs ngm-hub's src/setupcode.ts was given
local a = DC:Make("us", "Nootropic", {
    { name = "Guild Master", officer = true, invite = true },
    { name = "Officer", officer = true, invite = true },
    { name = "Recruiter", officer = false, invite = true },
    { name = "Raider", officer = false, invite = false },
    { name = "Offizi\195\168re \226\156\166", officer = false, invite = false },
})
assert(a == "NGM1.dXMKTm9vdHJvcGljCk9JOkd1aWxkIE1hc3RlcgpPSTpPZmZpY2VyCi1JOlJlY3J1aXRlcgotLTpSYWlkZXIKLS06T2ZmaXppw6hyZSDinKY.53821c96", a)
local b = DC:Make("eu", "Dragon's Fury", { { name = "GM", officer = true, invite = true }, { name = "M" } })
assert(b == "NGM1.ZXUKRHJhZ29uJ3MgRnVyeQpPSTpHTQotLTpN.7a0407fb", b)
assert(DC.Adler32("Wikipedia") == "11e60398")
assert(DC.Base64Url("f") == "Zg" and DC.Base64Url("fo") == "Zm8" and DC.Base64Url("foo") == "Zm9v" and DC.Base64Url("\255\254") == "__4")

-- the player's own guild
local gm, region, flags = true, 1, { [1] = { officer = true, invite = true }, [2] = { officer = false, invite = false } }
GetGuildInfo = function() return "Nootropic" end
GetCurrentRegion = function() return region end
ns.DB = { IsGuildMaster = function() return gm end,
  GuildRanks = function() return { { index = 0, name = "Guild Master" }, { index = 1, name = "Officer" }, { index = 2, name = "Member" } } end }
ns.Sync = { RankFlags = function(_, i) return flags[i] end }
local code = DC:ForMyGuild("setup")
assert(code and code:find("^NGM1%."), tostring(code))
gm = false
local none, why = DC:ForMyGuild()
assert(none == nil and why:find("Guild Master"))
gm, flags[2] = true, nil
none, why = DC:ForMyGuild()
assert(none == nil and why:find("settings"))
flags[2], region = { officer = false, invite = false }, 2
none, why = DC:ForMyGuild()
assert(none == nil and why:find("US and EU"))

-- NGM2, the update code: the same example as ngm-hub's test/gameupdate.test.ts
local counts = {}
for i = 0, 83 do counts[i + 1] = (i % 12 >= 9) and 3 or ((i % 5 == 0) and 1 or 0) end
local u = DC:MakeUpdate("us", "Nootropic", {
    { name = "Guild Master", officer = true, invite = true },
    { name = "Officer", officer = true, invite = true },
    { name = "Member", officer = false, invite = false },
}, { since = 1794000000, upto = 1794540000, hours = { sharing = 12, counts = counts }, records = {
    { key = "M:Zo\195\171 Ash", v = "Marc Priest", t = 1794500000, a = "Marc Priest" },
    { key = "M:Marc Priest", v = "", t = 1794500000, a = "Marc Priest" },
    { key = "RL:Zo\195\171 Ash", v = "tank,damage", t = 1794510000, a = "Zo\195\171 Ash" },
} })
assert(u == "NGM2.dXMKTm9vdHJvcGljCk9JOkd1aWxkIE1hc3RlcgpPSTpPZmZpY2VyCi0tOk1lbWJlcgoKc2luY2UJdG8zbjljCnVwdG8JdG9mN3hjCmhvdXJzCWMJMSwwLDAsMCwwLDEsMCwwLDAsMywzLDMsMCwwLDAsMSwwLDAsMCwwLDEsMywzLDMsMCwxLDAsMCwwLDAsMSwwLDAsMywzLDMsMCwwLDAsMCwxLDAsMCwwLDAsMywzLDMsMCwwLDEsMCwwLDAsMCwxLDAsMywzLDMsMSwwLDAsMCwwLDEsMCwwLDAsMywzLDMsMCwwLDAsMSwwLDAsMCwwLDEsMywzLDMKUglNOlpvw6sgQXNoCXRvZWQyOAlNYXJjIFByaWVzdAlNYXJjIFByaWVzdApSCU06TWFyYyBQcmllc3QJdG9lZDI4CU1hcmMgUHJpZXN0CQpSCVJMOlpvw6sgQXNoCXRvZWtzMAlab8OrIEFzaAl0YW5rLGRhbWFnZQ.13f06304", u)
assert(DC.B36(0) == "0" and DC.B36(35) == "z" and DC.B36(36) == "10")

-- the tabard's colours, for NGM Peon's accent (ngm-hub test/accent.test.ts reads the same line)
local withTabard = DC:MakeUpdate("us", "G", { { name = "GM", officer = true, invite = true }, { name = "M", officer = false, invite = false } },
    { since = 0, upto = 1, records = {}, tabard = { bg = "5b2a86", border = "d4a017" } })
local payload = DC.Base64UrlDecode(withTabard:match("^NGM2%.([^.]+)%."))
assert(payload:find("\naccent\t5b2a86,d4a017", 1, true), payload)
local without = DC:MakeUpdate("us", "G", { { name = "GM", officer = true, invite = true }, { name = "M", officer = false, invite = false } },
    { since = 0, upto = 1, records = {} })
assert(not DC.Base64UrlDecode(without:match("^NGM2%.([^.]+)%.")):find("accent", 1, true), "tabard unknown: no line")

-- only changes: since NGM Peon's word, else the last code less two weeks; "all" sends everything
local now = 3000000
local store = {
    ["M:Old"] = { v = "", t = 1000, a = "Old" },
    ["M:New"] = { v = "Main", t = now - 10, a = "Off" },
    ["RL:New"] = { v = "tank", t = now - 5, a = "New" },
    ["CN:New"] = { v = "x", t = now - 5, a = "New" }, -- not sent: only M and RL
    ["RL:Odd"] = { v = "admin", t = now - 5, a = "Odd" }, -- not sent: not a role
}
ns.Sync.ValidValue = function(typ, v)
    if typ == "RL" then return v == "" or not (v .. ","):gsub("tank,", ""):gsub("healer,", ""):gsub("damage,", ""):find("%S") end
    return true
end
local guildData = {}
gm, region, flags[2] = true, 1, { officer = false, invite = false }
ns.DB.Guild = function() return guildData end
ns.DB.Now = function() return now end
ns.Sync.Store = function() return store end
local first, _, everything = DC:ForMyGuild()
assert(first:find("^NGM2%.") and everything == true, "first code: everything")
assert(guildData.peon.made == now)
assert(#DC:Changes(0) == 3 and #DC:Changes(now - 8) == 1)
now = now + 30 * 86400
local _, _, all2 = DC:ForMyGuild()
assert(all2 == false, "later codes: changes only")
guildData.peon.has = now - 100
local _, _, all3 = DC:ForMyGuild("all")
assert(all3 == true, "/ngm discord all: everything")
assert(DC:ForMyGuild("setup"):find("^NGM1%."), "/ngm discord setup: the short code")
-- the tabard's colours go in the update code (both of them: test 15 lost the border)
ns.Accent = { Tabard = function() return "111111", "6a2c91", "3fae4a" end }
local withColours = DC.Base64UrlDecode(DC:ForMyGuild("all"):match("^NGM2%.([^.]+)%."))
assert(withColours:find("\naccent\t111111,6a2c91,3fae4a", 1, true), withColours)
ns.Accent = { Tabard = function() return nil end }
assert(not DC.Base64UrlDecode(DC:ForMyGuild("all"):match("^NGM2%.([^.]+)%.")):find("accent", 1, true))
ns.Accent = nil


-- NGMP1, the code from NGM Peon: the same example as ngm-hub's test/gameupdate.test.ts
local function hash(str) -- Core/Records.lua's Hash
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967291 end
    return h
end
ns.Sync.Hash = hash
assert(DC.Base64UrlDecode(DC.Base64Url("Zo\195\171 Ash, foo")) == "Zo\195\171 Ash, foo")
assert(DC.Base64UrlDecode("Zg") == "f" and DC.Base64UrlDecode("Zm8") == "fo" and DC.Base64UrlDecode("Zm9v") == "foo")
ns.Split = function(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return out
end
local pc = assert(DC:ParsePeon("NGMP1.dXMKTm9vdHJvcGljCmhhcwl0b2Y3eGMKaG91cnMJMW8xbnQxMwpSCU06Wm_DqyBBc2gJdG9naTgwCU1hcmMgUHJpZXN0CU1hcmMgUHJpZXN0ClIJUkw6TWFyYyBQcmllc3QJdG9naTgxCU1hcmMgUHJpZXN0CWhlYWxlcg.2a542997"))
assert(pc.region == "us" and pc.guild == "Nootropic" and pc.has == 1794540000, "header")
assert(pc.hoursHash == hash(DC.HoursValue({ sharing = 12, counts = counts })), "the grid's hash matches NGM Peon's")
assert(#pc.records == 2 and pc.records[1].key == "M:Zo\195\171 Ash" and pc.records[1].v == "Marc Priest" and pc.records[2].v == "healer")
assert(DC:ParsePeon("NGMP1.abc.00000000") == nil)

-- bringing it in: records through the usual rules, NGM Peon's word remembered
GetGuildInfo = function() return "Nootropic" end
region = 1
local held, sent = { ["RL:Marc Priest"] = { v = "healer", t = 1794600001, a = "Marc Priest" } }, {}
ns.PlayerFullName = function() return "Marc Priest" end
ns.Sync.Get = function(_, k) return held[k] end
ns.Sync.Intake = function(_, key, t, a, b, v, ctx) held[key] = { v = v, t = t, a = a }; return true, key end
ns.Sync.Broadcast = function(_, key) sent[#sent + 1] = key end
guildData = {}
ns.DB.Guild = function() return guildData end
local got = assert(DC:ApplyPeon("NGMP1.dXMKTm9vdHJvcGljCmhhcwl0b2Y3eGMKaG91cnMJMW8xbnQxMwpSCU06Wm_DqyBBc2gJdG9naTgwCU1hcmMgUHJpZXN0CU1hcmMgUHJpZXN0ClIJUkw6TWFyYyBQcmllc3QJdG9naTgxCU1hcmMgUHJpZXN0CWhlYWxlcg.2a542997"))
assert(got.taken == 1 and got.had == 1 and got.refused == 0, ("%d %d %d"):format(got.taken, got.had, got.refused))
assert(got.players == 1 and got.characters == 0 and got.names == 0, "counted by kind")
assert(sent[1] == "M:Zo\195\171 Ash" and guildData.peon.has == 1794540000)
-- a Discord name (CN) is taken too; other kinds aren't
do
    local payload = "us\nNootropic\nhas\t" .. DC.B36(1794540000) .. "\nhours\t" .. DC.B36(pc.hoursHash) .. "\nR\tCN:Marc Priest\t" .. DC.B36(1794600005) .. "\tMarc Priest\tkeasbeexd;\nR\tGS:perm_links\t" .. DC.B36(1794600005) .. "\tMarc Priest\t0"
    local code = "NGMP1." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
    local got2 = assert(DC:ApplyPeon(code))
    assert(got2.taken == 1 and got2.refused == 1, ("%d %d"):format(got2.taken, got2.refused))
    assert(got2.names == 1, "a Discord name counted")
    -- champions and the setting that NGM Peon crowns them; nothing else under GS
    local p3 = "us\nNootropic\nhas\t" .. DC.B36(1794540000) .. "\nhours\t" .. DC.B36(pc.hoursHash)
        .. "\nR\tHW:202610\t" .. DC.B36(1794600009) .. "\tNGM Peon\tquests=Pip Moss;kills=Marc Priest"
        .. "\nR\tGS:peon\t" .. DC.B36(1794600009) .. "\tNGM Peon\t1"
        .. "\nR\tGS:officers\t" .. DC.B36(1794600009) .. "\tNGM Peon\t0"
        .. "\nR\tHW:2026\t" .. DC.B36(1794600009) .. "\tNGM Peon\tx=y"
    local got3 = assert(DC:ApplyPeon("NGMP1." .. DC.Base64Url(p3) .. "." .. DC.Adler32(p3)))
    assert(got3.months == 1 and got3.taken == 2 and got3.refused == 2, ("%d %d %d"):format(got3.months, got3.taken, got3.refused))
    assert(held["GS:peon"].v == "1" and held["HW:202610"].v == "quests=Pip Moss;kills=Marc Priest")
    assert(held["CN:Marc Priest"].v == "keasbeexd;")
end

-- the next update code: changes since NGM Peon's word (less a week), and no grid when NGM Peon has the same
store = {}
ns.Sync.Store = function() return store end
now = 1794540000 + 86400
ns.DB.Now = function() return now end
ns.OverviewView = { Census = function() local h = {} for i = 0, 83 do h[i] = counts[i + 1] end return { heat = h, sharing = 12 } end }
local upd = DC:ForMyGuild()
local text = DC.Base64UrlDecode(upd:match("^NGM2%.([^.]+)%."))
assert(text:find("\nsince\t" .. DC.B36(1794540000 - DC.ARRIVAL) .. "\n", 1, true), "since NGM Peon's word, less a week")
assert(not text:find("\nhours\t", 1, true), "same grid as NGM Peon: not sent")
local all = DC.Base64UrlDecode(DC:ForMyGuild("all"):match("^NGM2%.([^.]+)%."))
assert(all:find("\nhours\t", 1, true), "everything: the grid too")


-- the reminder: the Guild Master of a guild using NGM Peon, once a day after 3 days; ranks changed: once per change
date = date or os.date
local peonat
ns.Sync.Value = function(_, k) return nil end
ns.Sync.Get = function(_, k) if k == "GS:peonat" and peonat then return { v = tostring(peonat), t = peonat } end return held[k] end
local told = {}
ns.Print = function(_, m) told[#told + 1] = m end
InCombatLockdown = function() return false end
gm = true
guildData = { peon = { made = 1000000, ranks = DC.RankSignature(assert(DC:MyRanks())) } }
ns.DB.Guild = function() return guildData end
peonat = 1000000
assert(DC:ReminderText(1000000 + 2 * 86400) == nil, "2 days: nothing yet")
assert(DC:Remind(1000000 + 4 * 86400), "4 days: told")
assert(told[#told]:find("best done daily", 1, true) and told[#told]:find("Game to Discord|r: last done 4 days ago", 1, true)
  and told[#told]:find("Discord to the game|r: last done 4 days ago", 1, true), told[#told])
assert(not DC:Remind(1000000 + 4 * 86400 + 3600), "once a day")
peonat = 1000000 + 4 * 86400 + 7200 -- an officer brought NGM Peon's code in
local only = DC:ReminderText(1000000 + 5 * 86400)
assert(only:find("Game to Discord", 1, true) and not only:find("Discord to the game", 1, true), "only what's overdue")
flags[2] = { officer = true, invite = false } -- a rank's permissions changed in game
assert(DC:Remind(1000000 + 5 * 86400 + 120) and told[#told]:find("ranks changed", 1, true), "ranks changed: told at once")
assert(not DC:Remind(1000000 + 5 * 86400 + 180), "the same change: once")
gm = false
assert(DC:ReminderText(1000000 + 30 * 86400) == nil, "only the Guild Master")
gm = true
guildData = {}
assert(DC:ReminderText(1000000 + 30 * 86400) == nil, "a guild not using NGM Peon: nothing")

print(a); print("OK")
