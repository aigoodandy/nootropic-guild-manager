-- Test: Upcoming Events from NGM Peon's code (the same example as ngm-hub's
-- EVENT_VECTOR): read with where to sign up and who's coming; an officer
-- shares them with the guild (EV records) and clears cancelled ones; anyone
-- else keeps them for themselves; past ones aren't listed; and the records'
-- rules (Core/Records.lua) take only well-formed ones.
local ROOT = arg[1]
date, time = os.date, os.time
local ns = {}
ns.GOLD, ns.ORANGE, ns.BLUE = "|cfffabd2f", "|cfffe8019", "|cff83a598"
ns.Split = function(s, sep)
    local out, from = {}, 1
    while true do
        local i = s:find(sep, from, true)
        if not i then out[#out + 1] = s:sub(from) break end
        out[#out + 1] = s:sub(from, i - 1)
        from = i + #sep
    end
    return out
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
assert(loadfile(ROOT .. "/Services/DiscordCode.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Events.lua"))("NGM", ns)
local DC, E = ns.DiscordCode, ns.Events

local c = assert(DC:ParsePeon("NGMP1.dXMKTm9vdHJvcGljCmhhcwl0b2Y3eGMKRQkxNglyYWlkCXRvaW8wMAk1MAlNb2x0ZW4gQ29yZQlCcmluZyBmaXJlIHJlc2lzdC4gT24gdGltZSEJcmFpZHMJTm9vdHJvcGljCWM.87cb2139"))
local ev = c.events[1]
assert(ev.id == 42 and ev.kind == "raid" and ev.starts == 1794700800 and ev.minutes == 180 and ev.title == "Molten Core"
  and ev.description == "Bring fire resist. On time!" and ev.channel == "raids" and ev.server == "Nootropic" and ev.coming == 12)

-- a guild record round trip
local back = E.Parse("16", E.Value(ev))
for _, k in ipairs({ "kind", "starts", "minutes", "coming", "channel", "server", "title", "description" }) do assert(back[k] == ev[k], k) end
assert(E.Parse("x", "") == nil, "cleared: gone")

-- someone who isn't an officer: kept for themselves
local now = 1794600000
local guild, store, officer = {}, {}, false
ns.DB = { Guild = function() return guild end, Now = function() return now end }
ns.Sync = { CanWrite = function() return officer end, Get = function(_, k) return store[k] end,
  Set = function(_, k, v) store[k] = { v = v } end, Store = function() return store end }
local up, new, removed = E:Take(c.events)
assert(up == 1 and new == 1 and removed == 0 and next(store) == nil, "not shared")
assert(E:List()[1].title == "Molten Core")

-- an officer: shared with the guild; one NGM Peon no longer has is cleared
officer = true
store["EV:z"] = { v = E.Value({ kind = "event", starts = now + 3600, minutes = 60, coming = 0, channel = "", server = "", title = "Old", description = "" }) }
up, new, removed = E:Take(c.events)
assert(up == 1 and new == 0 and removed == 1, "the old one, cancelled: 1 event removed")
assert(store["EV:16"] and store["EV:16"].v == E.Value(ev), "shared as EV:<id>")
assert(store["EV:z"].v == "", "cancelled in Discord: cleared")
-- past events aren't listed, and one that has started isn't "removed"
now = ev.starts + 1
assert(#E:List() == 0)
up, new, removed = E:Take({})
assert(up == 0 and new == 0 and removed == 0)

-- the records' rules
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns)
local S = ns.Sync
assert(S and S.ValidValue, "the records code loaded")
do
    assert(S.ValidValue("EV", E.Value(ev)) and S.ValidValue("EV", ""))
    assert(not S.ValidValue("EV", "party;1;1;0;x;y;z;"), "an unknown kind")
    assert(not S.ValidValue("EV", "raid;1;1;0;x\ty;y;z;"), "no tabs")
    -- their own sync lane: a 2.12 copy ignores lanes it doesn't know, so
    -- events never make its fingerprints differ from a 3.0 officer's
    assert(S.LaneOf("EV:16") == "events" and S.LaneOf("M:Marc") == "guild")
    assert(S.LANE_STORE.events == "guild" and S.LANE_CHANNEL.events == "GUILD")
end
print("OK")
