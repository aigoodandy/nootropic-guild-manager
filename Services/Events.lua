--[[
    Nootropic Guild Manager - Upcoming Events (from NGM Peon)
    NGM Peon's code (/ngm peon) carries the guild's events for the next 30
    days: when, what, how long, how many are coming, and the Discord channel
    and server to sign up in. The Upcoming Events tab lists them, as the
    dashboard's Upcoming Events tab does. (The WoW calendar can't take
    them: the game only lets its own interface fill an event in.)

    An officer bringing the code in writes each as a guild record (EV:<id>,
    Core/Records.lua), so everyone's addon gets them through guild sync;
    events gone from NGM Peon (cancelled) are cleared. Anyone else keeps
    the code's events for themselves.

      ns.Events:Take(events)   the code's events -> upcoming, new, removed (counts)
      ns.Events:List()         upcoming events, soonest first
]]
local _, ns = ...
local E = {}
ns.Events = E

local function B36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local s, d = "", "0123456789abcdefghijklmnopqrstuvwxyz"
    while n > 0 do
        local r = n % 36
        s = d:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end
local function Clean(s) return ((s or ""):gsub("[;\t\n]", ",")) end

function E.Value(ev)
    return table.concat({ ev.kind, B36(ev.starts), B36(ev.minutes), B36(ev.coming or 0), Clean(ev.channel), Clean(ev.server), Clean(ev.title), Clean(ev.description) }, ";")
end

function E.Parse(id, v)
    if not v or v == "" then return nil end
    local f = {}
    for part in (v .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
    local starts, minutes, coming = tonumber(f[2] or "", 36), tonumber(f[3] or "", 36), tonumber(f[4] or "", 36)
    if not (starts and minutes) then return nil end
    return { id = tonumber(id, 36) or 0, kind = f[1], starts = starts, minutes = minutes, coming = coming or 0, channel = f[5] or "", server = f[6] or "",
             title = f[7] or "", description = table.concat(f, ";", 8) }
end

local function Local()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.upcoming = g.upcoming or {}
    g.calendar = nil -- the old "Add to calendar" list
    return g.upcoming
end

function E:Take(events)
    events = events or {}
    local now = ns.DB:Now()
    local key = function(ev) return "EV:" .. B36(ev.id) end
    -- what was listed before, to say what's new and what's gone
    local before = {}
    for _, ev in ipairs(self:List()) do before[B36(ev.id)] = ev.starts end
    if ns.Sync and ns.Sync.CanWrite and ns.Sync:CanWrite("EV:0") then
        -- an officer: for the whole guild
        local wanted = {}
        for _, ev in ipairs(events) do
            local k, v = key(ev), E.Value(ev)
            wanted[k] = true
            local cur = ns.Sync:Get(k)
            if not cur or cur.v ~= v then ns.Sync:Set(k, v) end
        end
        -- upcoming ones NGM Peon no longer has (cancelled): cleared
        for k, rec in pairs(ns.Sync:Store("guild") or {}) do
            if k:sub(1, 3) == "EV:" and not wanted[k] and rec.v ~= "" then
                local ev = E.Parse(k:sub(4), rec.v)
                if ev and ev.starts > now then ns.Sync:Set(k, "") end
            end
        end
    end
    local l = Local()
    if l then
        wipe(l)
        for _, ev in ipairs(events) do l[#l + 1] = ev end
    end
    local list = self:List()
    local added, after = 0, {}
    for _, ev in ipairs(list) do
        local id = B36(ev.id)
        after[id] = true
        if not before[id] then added = added + 1 end
    end
    local removed = 0
    -- gone from NGM Peon while still to come (one that has started isn't "removed")
    for id, starts in pairs(before) do if not after[id] and starts > now then removed = removed + 1 end end
    return #list, added, removed
end

function E:List()
    local now, byId, list = ns.DB:Now(), {}, {}
    for k, rec in pairs((ns.Sync and ns.Sync.Store and ns.Sync:Store("guild")) or {}) do
        if k:sub(1, 3) == "EV:" then
            local ev = E.Parse(k:sub(4), rec.v)
            if ev and ev.starts > now then byId[k:sub(4)] = ev end
        end
    end
    -- what this character brought in itself (not an officer: not shared)
    for _, ev in ipairs(Local() or {}) do
        local id = B36(ev.id)
        if not byId[id] and ev.starts > now then byId[id] = ev end
    end
    for _, ev in pairs(byId) do list[#list + 1] = ev end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    return list
end

function E:Init() end
