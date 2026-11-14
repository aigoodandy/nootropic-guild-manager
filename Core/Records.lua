--[[
    Nootropic Guild Manager - Records

    Everything the guild shares is a RECORD: key -> { v = value, t = time,
    a = author, b = batch }. Every change gets the server time and its
    author, and the newest version always wins (ties broken by author, then
    value), so every copy converges on the same data whatever order changes
    arrive in.

    This file is the data and its rules: record types, who may write what,
    limits, the newest-wins rule, and turning records into the addon's
    working data. It knows nothing about how records travel; Core/Sync.lua
    carries them between players in game (and the NGM Hub will carry the
    same records, under the same rules, in 3.0). See docs/ARCHITECTURE.md.

    Scopes
      guild    shared with the whole guild (the guild addon channel)
      officer  officers only (the officer addon channel)

    Record keys (who may write them: see MayAuthor; docs/ARCHITECTURE.md)
      M:<member>           their main ("" = a main)
      MS:<member>          spec override
      RL:<member>          roles: "tank,healer,damage" (any of them)
      MP:<member>          manual professions
      CN:<member>          contact: "discord;note"
      P:<member>           spec and professions their addon read
      AV:<member>          addon version in use
      SC:<member>          usual online hours: 168 bits (Monday 00:00 UTC on) as 42 hex digits
      RP:<member>:<prof>   recipes in one profession: "name;id,id" (base-36 spell IDs)
      RR:<member>          raid readiness: attunements and keys
      PS:<member>          sharing choices others must respect ("together")
      HF:<member>          Hall of Fame statistics
      HX:<member>          left out of the Hall of Fame: "1" ("" = shown)
      HW:<month>           that month's champions: "quests=Name,Name;kills=Name"
      HA:<month>           that month's champions were announced: "<time>"
      EV:<id>              an upcoming event from NGM Peon (Services/Events.lua):
                           "kind;starts;minutes;coming;channel;server;title;description"
                           (numbers base 36; "" = gone)
      DN:<player>          Do Not Whisper entry ("" = removed)
      RS:<player>          recruitment status (kept 14 days)
      IR:<member>          reminded to install the addon (kept 30 days)
      GS:<name>            guild setting; GS:perm_* (who may do what),
                           GS:officers and GS:recruiters (rank names, from the
                           game's rank settings) only from the Guild Master
      L:<member>:<id>      officer log entry                 (officer scope)
      A:<id>               audit entry                       (officer scope)
      JN:<member>          when they joined: "time;inviter"  (officer scope)
      RK:<member>          rank since: "time;rank;by"        (officer scope)
      HC:<member>          Hall of Fame numbers checked      (officer scope)

    Types with a ttl expire: older records are deleted and refused.
]]
local _, ns = ...
local S = {}
ns.Sync = S

S.FS = "\t"
local US = "\031" -- separator inside audit values
S.US = US

S.AUDIT_SYNC_WINDOW = 30 * 86400 -- audit older than this isn't compared (retention differs per officer)
S.BATCH_DELAY = 15               -- local changes are sent together after this many seconds

S.TYPES = {
    M  = { scope = "guild",   officer = true, label = "Main / Alt" },
    MS = { scope = "guild",   officer = true, self = true, label = "Spec" },
    RL = { scope = "guild",   officer = true, self = true, label = "Role" },
    MP = { scope = "guild",   officer = true, self = true, label = "Professions" },
    P  = { scope = "guild",   selfOnly = true, label = "Reported spec / professions" },
    L  = { scope = "officer", officer = true, label = "Officer log" },
    A  = { scope = "officer", officer = true, noAudit = true, label = "Audit" },
    DN = { scope = "guild",   anyone = true, label = "Do Not Whisper" },
    RS = { scope = "guild",   anyone = true, noAudit = true, ttl = 14 * 86400, label = "Recruitment status" },
    AV = { scope = "guild",   selfOnly = true, noAudit = true, label = "Addon version" },
    GS = { scope = "guild",   officer = true, label = "Guild setting" },
    CN = { scope = "guild",   officer = true, self = true, label = "Contact" },
    SC = { scope = "guild",   selfOnly = true, noAudit = true, label = "Usually online" },
    RP = { scope = "guild",   selfOnly = true, noAudit = true, low = true, label = "Recipes" },
    RR = { scope = "guild",   selfOnly = true, noAudit = true, label = "Raid readiness" },
    PS = { scope = "guild",   selfOnly = true, noAudit = true, label = "Sharing choices" },
    HF = { scope = "guild",   selfOnly = true, noAudit = true, low = true, label = "Hall of Fame" },
    IR = { scope = "guild",   anyone = true, noAudit = true, ttl = 30 * 86400, label = "Install reminder" },
    HX = { scope = "guild",   officer = true, label = "Hidden from Hall of Fame" },
    HW = { scope = "guild",   officer = true, noAudit = true, label = "Hall of Fame champions" },
    HA = { scope = "guild",   officer = true, noAudit = true, label = "Champions announced" },
    EV = { scope = "guild",   officer = true, noAudit = true, label = "Upcoming event" },
    HC = { scope = "officer", officer = true, noAudit = true, label = "Hall of Fame check" },
    JN = { scope = "officer", officer = true, noAudit = true, label = "Joined" },
    RK = { scope = "officer", officer = true, noAudit = true, label = "Rank since" },
}
-- Audit entry kinds that aren't records: changes to the guild roster itself
-- (Services/RosterLog.lua). GM joined/left, GK promoted/demoted, LV level,
-- GN public/officer note, NC name change.
S.ROSTER_EVENTS = { GM = true, GK = true, LV = true, GN = true, NC = true }
S.EVENT_DEDUPE = 6 * 3600 -- event-log times are only known to the hour

-- Same event seen by two officers: same signature. nil for kinds that
-- don't need it (their ids already match).
function S.EventSig(typ, member, new)
    if typ ~= "GM" and typ ~= "GK" then return nil end
    if new == "rejoin" then new = "join" end
    return typ .. "|" .. (member or "") .. "|" .. (new or "")
end
-- Types whose key is not about one member.
local NO_MEMBER = { A = true, GS = true, HW = true, HA = true, EV = true }

S.storeVersion = 0
S.officers = {} -- name -> rank index when seen sending on the officer channel this session
S.stats = { sent = 0, received = 0, applied = 0, refused = 0, dropped = 0 }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Now() return ns.DB:Now() end
local function Me() return ns.PlayerFullName() end

-- Simple string hash, kept below 2^32 (exact in Lua numbers).
local function Hash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967291 end
    return h
end
S.Hash = Hash

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        table.insert(out, 1, B36:sub(d + 1, d + 1))
        n = math.floor(n / 36)
    end
    return table.concat(out)
end
S.Base36 = Base36

-- Values never contain tabs/newlines (message separators) or "|" (the
-- game's escape character, which would garble chat and text display).
local function Clean(v)
    return (tostring(v or ""):gsub("[\t\r\n]", " "):gsub(US, ""):gsub("|", "/"))
end
S.Clean = Clean

function S.ParseKey(key)
    local typ, rest = key:match("^(%u+):(.*)$")
    if not typ or not S.TYPES[typ] then return nil end
    local member
    if typ == "L" or typ == "RP" then
        member = rest:match("^([^:]+):")
    elseif not NO_MEMBER[typ] then
        member = rest
    end
    return typ, member, rest
end

------------------------------------------------------------------------
-- Names without shard tags (WoW: Forever; see ns.NormalizeName)
-- Older copies of the addon still send "Name-<shard>"; every key, author
-- and name inside a value is brought to the plain name before it's checked
-- or stored, so everyone's copy keeps one record per person.
------------------------------------------------------------------------
local function CN(name)
    if not name or name == "" then return name end
    return ns.NormalizeName(name) or name
end
S.CanonName = CN

-- key -> the same key with plain names
function S.CanonKey(key)
    if not ns.NO_REALMS then return key end
    local typ, rest = key:match("^(%u+):(.*)$")
    if not typ or NO_MEMBER[typ] then return key end
    if typ == "L" or typ == "RP" then
        local member, tail = rest:match("^([^:]+):(.*)$")
        if not member then return key end
        return typ .. ":" .. CN(member) .. ":" .. tail
    end
    return typ .. ":" .. CN(rest)
end

-- Names inside values: mains, who invited or promoted, audit entries.
function S.CanonValue(typ, v)
    if not ns.NO_REALMS or not v or v == "" then return v end
    if typ == "M" then return CN(v) end
    if typ == "JN" then
        local t, by = v:match("^(%d+);(.*)$")
        if t then return t .. ";" .. (by ~= "" and CN(by) or "") end
    elseif typ == "RK" then
        local t, rank, by = v:match("^(%d+);([^;]*);(.*)$")
        if t then return t .. ";" .. rank .. ";" .. (by ~= "" and CN(by) or "") end
    elseif typ == "A" then
        local f = ns.Split(v, US)
        if #f >= 4 then
            f[1] = CN(f[1])
            if f[2] == "M" then f[3], f[4] = CN(f[3]), CN(f[4]) end
            return table.concat(f, US)
        end
    end
    return v
end

-- (key, rec) -> plain-name key and the record with its author and values tidied
function S.Canon(key, rec)
    if not ns.NO_REALMS then return key, rec end
    local ck = S.CanonKey(key)
    local typ = ck:match("^(%u+):")
    rec.a = CN(rec.a)
    rec.v = S.CanonValue(typ, rec.v)
    return ck, rec
end

-- One pass over saved data from before 2.7.2: records, private notes,
-- recruit history and your own per-character settings move to plain names.
-- Where two records become one, the newer wins (the same rule as sync), so
-- every copy ends up identical.
function S:CanonicalizeSaved()
    local g = ns.DB:Guild()
    if not ns.NO_REALMS or not g or g.realmless then return 0 end
    local moved = 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        local out = {}
        for key, rec in pairs(store) do
            local before = key .. "\0" .. tostring(rec.a) .. "\0" .. tostring(rec.v)
            local ck, r = S.Canon(key, rec)
            if ck .. "\0" .. tostring(r.a) .. "\0" .. tostring(r.v) ~= before then moved = moved + 1 end
            local cur = out[ck]
            if not cur or S.Newer(r, cur) then out[ck] = r end
        end
        for k in pairs(store) do store[k] = nil end
        for k, r in pairs(out) do store[k] = r end
    end
    local function rekey(t, merge)
        if type(t) ~= "table" then return end
        local keys = {}
        for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
        for _, k in ipairs(keys) do
            local ck = CN(k)
            if ck ~= k then
                local v = t[k]
                t[k] = nil
                if t[ck] == nil then t[ck] = v elseif merge then merge(t[ck], v) end
                moved = moved + 1
            end
        end
    end
    rekey(g.members, function(cur, m)
        if m.note and m.note ~= "" and m.note ~= cur.note then
            cur.note = (cur.note and cur.note ~= "") and (cur.note .. " / " .. m.note) or m.note
        end
    end)
    if g.recruit then rekey(g.recruit.people) end
    local s = ns.DB:Settings()
    rekey(s.schedules)
    rekey(s.hof)
    g.realmless = true
    self.auditCache = nil
    return moved
end

-- When a record stops being kept (server time), or nil when it never expires.
function S:ExpiresAt(key, rec)
    local typ = S.ParseKey(key)
    if not typ then return nil end
    local def = S.TYPES[typ]
    return def.ttl and rec.t + def.ttl or nil
end

local function Newer(a, b)
    if a.t ~= b.t then return a.t > b.t end
    local aa, ba = a.a or "", b.a or ""
    if aa ~= ba then return aa > ba end
    return (a.v or "") > (b.v or "")
end
S.Newer = Newer

function S:Store(scope)
    local g = ns.DB:Guild()
    if not g then return nil end
    g.sync = g.sync or {}
    g.sync[scope] = g.sync[scope] or {}
    return g.sync[scope]
end

function S:Get(key)
    local typ = S.ParseKey(key)
    if not typ then return nil end
    local store = self:Store(S.TYPES[typ].scope)
    return store and store[key]
end

function S:Value(key)
    local rec = self:Get(key)
    return rec and rec.v
end

------------------------------------------------------------------------
-- Permissions
------------------------------------------------------------------------
function S:CanWrite(key)
    local typ, member, rest = S.ParseKey(key)
    if not typ then return false end
    local def = S.TYPES[typ]
    if def.selfOnly then return member == Me() end
    if def.anyone then return IsInGuild() end -- (DN removal is checked in RC:RemoveDNW)
    -- your own profile: the Guild Master decides (everyone by default)
    if def.self and member == Me() and ns.DB:HasPerm("ownprofile") then return true end
    -- permissions only the Guild Master changes
    if typ == "GS" and (rest:sub(1, 5) == "perm_" or rest == "officers" or rest == "recruiters") then return ns.DB:IsGuildMaster() end
    -- what the Guild Master hands out per rank (Options > Officers > Permissions)
    local perm = def.scope == "guild" and ns.DB.PERM_BY_TYPE[typ]
    if perm then return ns.DB:HasPerm(perm) end
    if def.officer and ns.IsOfficer() then return true end
    return false
end

------------------------------------------------------------------------
-- Who may send a record. A record's author (rec.a) is only what the sender
-- claims; the sender is the one name the game vouches for. So:
--   * the author must be allowed to write the record (rank, permissions,
--     their own profile), checked against the guild roster
--   * a record someone else wrote may only be passed on by an officer:
--     the Guild Master, a rank in GS:officers (written only by the Guild
--     Master), or someone seen on the officer channel (which the game only
--     delivers to and from officer ranks), always at their current rank
--   * Guild Master permission settings must name the current Guild Master
--     as author, whoever passes them on
-- Without this any guildmate could forge permission changes or anyone's
-- profile with one hand-made addon message.
------------------------------------------------------------------------
local function Same(a, b) return a and b and a:lower() == b:lower() end

local function RosterEntry(name)
    if not name then return nil end
    local e = ns.Roster.byName[name]
    if e then return e end
    local lower = name:lower()
    for full, entry in pairs(ns.Roster.byName) do
        if full:lower() == lower then return entry end
    end
end

local function IsGuildMaster(name)
    local e = RosterEntry(name)
    return e ~= nil and e.rankIndex == 0
end
S.Same, S.RosterEntry, S.IsGuildMaster = Same, RosterEntry, IsGuildMaster

------------------------------------------------------------------------
-- Lanes: what's compared together, and on which channel.
--   guild    guild records, except recruitment statuses     GUILD
--   recruit  recruitment statuses (RS), only between members who may
--            recruit (nobody else keeps them)                GUILD
--   officer  officer records                                 OFFICER
--   events   Upcoming Events (EV, 3.0): their own lane, so a 2.12 copy
--            (which ignores lanes it doesn't know) never sees them in a
--            fingerprint and never keeps re-checking over them      GUILD
------------------------------------------------------------------------
S.LANES = { "guild", "recruit", "officer", "events" }
S.LANE_STORE = { guild = "guild", recruit = "guild", officer = "officer", events = "guild" }
S.LANE_CHANNEL = { guild = "GUILD", recruit = "GUILD", officer = "OFFICER", events = "GUILD" }

function S.LaneOf(key)
    local typ = key:match("^(%u+):")
    if typ == "RS" then return "recruit" end
    if typ == "EV" then return "events" end
    local def = typ and S.TYPES[typ]
    return def and def.scope
end

function S:MayRecruit()
    return ns.Recruit and ns.Recruit.MayRecruit and ns.Recruit:MayRecruit() and true or false
end

-- Are we in this lane?
function S:InLane(lane)
    if lane == "officer" then return ns.IsOfficer() end
    if lane == "recruit" then return self:MayRecruit() end
    return lane == "guild" or lane == "events"
end

-- Will guildmates accept other people's records of this lane from `name`?
-- (Recruitment statuses from anyone; the officer channel is officers only;
-- other guild records only from officers. See SenderAllowed.)
function S:MayRelay(name, lane)
    if lane == "recruit" or lane == "officer" then return true end
    return self:KnownOfficer(name)
end

------------------------------------------------------------------------
-- Officers and recruiters follow the game's own rank settings (Guild
-- Control: "Officer" and "Invite"). For you, the game says directly. For
-- others, every copy reads the rank's settings when the game lets it, and
-- the Guild Master's copy also writes them down for everyone (GS:officers
-- and GS:recruiters: rank names, only the current Guild Master may write
-- them), for copies the game doesn't tell.
------------------------------------------------------------------------
S.FLAG_INVITE, S.FLAG_OFFICER = 5, 22 -- Blizzard_GuildControlUI: InviteCheckbox, OfficerCheckbox

-- { officer = bool, invite = bool } for a rank (0 = Guild Master), or nil
-- when the game won't say. Cached a minute.
S.flagCache = {}
function S:RankFlags(rankIndex)
    local c = self.flagCache[rankIndex]
    if c and GetTime() - c.at < 60 then return c.flags end
    local flags
    local api = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
    if api and rankIndex then
        local ok, t = pcall(api, rankIndex + 1)
        -- (every rank has some setting, guild chat at least: all off means
        -- the game isn't telling us)
        local any = false
        if ok and type(t) == "table" then for _, v in pairs(t) do if v == true then any = true break end end end
        if any then
            flags = { officer = t[self.FLAG_OFFICER] == true, invite = t[self.FLAG_INVITE] == true }
        end
    end
    self.flagCache[rankIndex or -1] = { at = GetTime(), flags = flags }
    return flags
end

local function RankSet(key)
    local rec = S:Get(key)
    if not rec or (rec.v or "") == "" or not IsGuildMaster(rec.a) then return nil end
    local set = {}
    for r in rec.v:gmatch("[^;]+") do set[r:lower()] = true end
    return set
end
function S:OfficerRanks() return RankSet("GS:officers") end
function S:RecruiterRanks() return RankSet("GS:recruiters") end

-- The Guild Master's copy: writes down which ranks are officer and invite
-- ranks, from the game's settings (or, if the game won't say even to the
-- Guild Master, ranks it has seen using the officer channel).
function S:PublishRanks()
    if not (ns.DB.IsGuildMaster and ns.DB:IsGuildMaster()) then return end
    local officers, recruiters, known = {}, {}, true
    for _, r in ipairs(ns.DB:GuildRanks()) do
        if r.index ~= 0 and not r.name:find(";", 1, true) then
            local f = self:RankFlags(r.index)
            if not f then known = false break end
            if f.officer then officers[#officers + 1] = r.name end
            if f.invite then recruiters[#recruiters + 1] = r.name end
        end
    end
    if not known then return end
    for key, list in pairs({ ["GS:officers"] = officers, ["GS:recruiters"] = recruiters }) do
        local v = table.concat(list, ";")
        if v ~= (self:Value(key) or "") then self:Set(key, v, { force = true }) end
    end
end

-- The Guild Master's copy, when the game won't tell it the rank settings:
-- someone of this rank used the officer channel, so it's an officer rank.
function S:NoteOfficer(who)
    if not (ns.DB.IsGuildMaster and ns.DB:IsGuildMaster()) then return end
    local e = RosterEntry(who)
    if not e or e.rankIndex == 0 or not e.rank or e.rank == "" or e.rank:find(";", 1, true) then return end
    if self:RankFlags(e.rankIndex) then return end -- the game's settings are written down instead
    local set = self:OfficerRanks() or {}
    if set[e.rank:lower()] then return end
    local names = {}
    for _, r in ipairs(ns.DB:GuildRanks()) do
        if r.index ~= 0 and (set[r.name:lower()] or r.name == e.rank) then names[#names + 1] = r.name end
    end
    self:Set("GS:officers", table.concat(names, ";"), { force = true })
end

-- An officer: the Guild Master, a rank the game marks Officer (or the
-- Guild Master's copy wrote down), or someone seen on the officer channel
-- this session who hasn't been demoted since. Always by current rank, so a
-- demoted or departed officer stops counting at once. With nothing known
-- yet (a new install, the Guild Master offline): the rank just below the
-- Guild Master, the officer rank in almost every guild.
function S:KnownOfficer(name)
    if not name then return false end
    if Same(name, Me()) then return ns.IsOfficer() end
    local e = RosterEntry(name)
    if not e then return false end
    if e.rankIndex == 0 then return true end
    for who, rankIndex in pairs(self.officers) do
        if Same(who, name) and e.rankIndex <= rankIndex then return true end
    end
    return self:RankIsOfficer(e)
end

-- Is this rank ({ rankIndex, rank }) an officer rank, as far as we know?
function S:RankIsOfficer(e)
    local f = self:RankFlags(e.rankIndex)
    if f then return f.officer end
    local ranks = self:OfficerRanks()
    if not ranks then return e.rankIndex == 1 end
    return e.rank ~= nil and ranks[e.rank:lower()] == true
end

-- May `name` recruit? The rank's Invite setting, the same way.
function S:MayRecruitName(name)
    if not name then return false end
    if Same(name, Me()) then return self:MayRecruit() end
    local e = RosterEntry(name)
    if not e then return false end
    if e.rankIndex == 0 then return true end
    local f = self:RankFlags(e.rankIndex)
    if f then return f.invite end
    local ranks = self:RecruiterRanks()
    if not ranks then return self:KnownOfficer(name) end
    return e.rank ~= nil and ranks[e.rank:lower()] == true
end

-- Would `name` be allowed to write this record themselves?
function S:MayAuthor(name, typ, member, rest)
    local def = S.TYPES[typ]
    if not (def and name and name ~= "") then return false end
    if def.anyone then return RosterEntry(name) ~= nil end
    if def.selfOnly then return Same(name, member) end
    if typ == "GS" and (rest:sub(1, 5) == "perm_" or rest == "officers" or rest == "recruiters") then return IsGuildMaster(name) end
    if def.self and Same(name, member) and self:RankMay(name, "ownprofile") then return true end
    local e = RosterEntry(name)
    if e and e.rankIndex == 0 then return true end
    local perm = def.scope == "guild" and ns.DB.PERM_BY_TYPE[typ]
    if perm then
        local set = ns.DB:PermRanks(perm)
        if set then return e ~= nil and set[e.rankIndex] == true end
        local pdef = ns.DB:PermDef(perm)
        if pdef and pdef.everyone then return e ~= nil end
    end
    if def.officer then return self:KnownOfficer(name) end
    return false
end

-- May `name` (a guildmate) do what the Guild Master allows for `perm`?
function S:RankMay(name, perm)
    local e = RosterEntry(name)
    if not e then return false end
    if e.rankIndex == 0 then return true end
    local set = ns.DB:PermRanks(perm)
    if set then return set[e.rankIndex] == true end
    local pdef = ns.DB:PermDef(perm)
    if pdef and pdef.everyone then return true end
    return self:KnownOfficer(name)
end

function S:SenderAllowed(typ, member, rest, def, rec, ctx)
    if def.scope == "officer" then return true end -- officer channel: officers only, by the game
    local sender, author = ctx.sender, rec.a
    -- anyone may put someone on the Do Not Whisper list; taking them off
    -- needs the recruit permission
    if typ == "DN" and (rec.v or "") == "" then
        return self:MayRecruitName(author) and (Same(sender, author) or self:KnownOfficer(sender))
    end
    -- install reminders say who sent them: only that person (or an officer
    -- passing it on) may send one, so nobody can block reminders for the
    -- whole guild in someone else's name
    if typ == "IR" then return Same(sender, author) or self:KnownOfficer(sender) end
    if def.anyone then return true end
    if typ == "GS" and (rest:sub(1, 5) == "perm_" or rest == "officers" or rest == "recruiters") then
        return IsGuildMaster(author) and (Same(sender, author) or self:KnownOfficer(sender))
    end
    if Same(sender, author) then return self:MayAuthor(author, typ, member, rest) end
    -- passing on someone else's record: officers only, and self-only
    -- records must still be the member's own
    if not self:KnownOfficer(sender) then return false end
    if def.selfOnly and not Same(author, member) then return false end
    return true
end

-- Limits on what one guildmate can add (not who may write what, which is
-- SenderAllowed): a hand-made client could otherwise flood everyone's saved
-- data with records it's allowed to write (its own recipe lists under
-- made-up professions, Do Not Whisper entries...).
S.MAX_VALUE = 4000            -- bytes in one value (ours are far smaller)
S.MAX_PROFESSIONS = 12        -- recipe lists (RP) per member
S.NEW_KEYS_PER_WINDOW = 500   -- new records one non-officer may add...
S.NEW_KEYS_WINDOW = 600       -- ...per 10 minutes
local newKeys = {}            -- sender -> { count, since }

-- Roles are only the addon's role keys; a main is "" or a plain name. A
-- hand-made client could otherwise spread junk that rides into NGM Peon's
-- update code (which refuses it, but it's never wanted anywhere).
function S.ValidValue(typ, v)
    v = v or ""
    if typ == "RL" then
        if v == "" then return true end
        for part in (v .. ","):gmatch("([^,]*),") do
            if part ~= "tank" and part ~= "healer" and part ~= "damage" then return false end
        end
        return true
    elseif typ == "M" then
        return v == "" or (#v <= 40 and not v:find("[,:\t]"))
    elseif typ == "EV" then
        if v == "" then return true end
        if #v > 600 or v:find("[\t\n]") then return false end
        local kind, starts, minutes, coming = v:match("^(%l+);(%w+);(%w+);(%w+);")
        return (kind == "dungeon" or kind == "raid" or kind == "event") and tonumber(starts, 36) ~= nil
            and tonumber(minutes, 36) ~= nil and tonumber(coming, 36) ~= nil
    end
    return true
end

function S:WithinLimits(typ, member, rest, rec, ctx, store)
    if #(rec.v or "") > self.MAX_VALUE then return false end
    if not S.ValidValue(typ, rec.v) then return false end
    if (typ == "HW" or typ == "HA") and not rest:match("^%d%d%d%d%d%d$") then return false end
    if typ == "EV" and not rest:match("^%w+$") then return false end
    -- reminders only about guildmates, holding the time they were sent
    if typ == "IR" then
        if not RosterEntry(member) then return false end
        local v = rec.v or ""
        if v ~= "" and not (v:match("^%d+$") and math.abs(tonumber(v) - rec.t) < 86400) then return false end
    end
    if typ == "RP" then
        if not rest:match("^[^:]+:%d+$") then return false end
        if not store[ctx.key] then
            local prefix, n = "RP:" .. member .. ":", 0
            for key in pairs(store) do
                if key:sub(1, #prefix) == prefix then n = n + 1 end
            end
            if n >= self.MAX_PROFESSIONS then return false end
        end
    end
    if not store[ctx.key] and not self:KnownOfficer(ctx.sender) then
        local now = GetTime()
        local c = newKeys[ctx.sender]
        if not c or now - c.since > self.NEW_KEYS_WINDOW then
            c = { count = 0, since = now }
            newKeys[ctx.sender] = c
        end
        if c.count >= self.NEW_KEYS_PER_WINDOW then return false end
        c.count = c.count + 1
    end
    return true
end

-- Counts a refused record and remembers the last one (for /ngm sync).
function S:Refuse(ctx, rec, why)
    self.stats.refused = self.stats.refused + 1
    self.lastRefused = { sender = ctx.sender, key = ctx.key, author = rec.a, why = why, at = Now() }
    return false
end

function S:Accept(typ, member, def, rec, ctx)
    if def.scope == "officer" then
        -- the game only delivers the officer channel to officer ranks
        if ctx.channel ~= "OFFICER" or not ns.IsOfficer() then return false end
    elseif ctx.channel ~= "GUILD" then
        return false
    end
    if def.selfOnly and rec.a ~= member then return self:Refuse(ctx, rec, "its author isn't the member it's about") end
    if not self:SenderAllowed(typ, member, select(3, S.ParseKey(ctx.key)) or "", def, rec, ctx) then
        return self:Refuse(ctx, rec, "the sender may not write it")
    end
    if rec.t > Now() + 300 then return self:Refuse(ctx, rec, "its time is in the future (clock?)") end
    if typ == "A" and rec.t < Now() - self:RetentionSeconds() then return false end
    local expires = self:ExpiresAt(ctx.key, rec)
    if expires and expires < Now() then return false end
    if not self:WithinLimits(typ, member, select(3, S.ParseKey(ctx.key)) or "", rec, ctx, self:Store(def.scope) or {}) then
        return self:Refuse(ctx, rec, "over a size or rate limit")
    end
    return true
end

-- Records left out of sync checks: old audit entries (each officer keeps a
-- different amount) and anything past its expiry.
function S:Excluded(key, rec, now)
    now = now or Now()
    if key:sub(1, 2) == "A:" then return rec.t < now - self.AUDIT_SYNC_WINDOW end
    local expires = self:ExpiresAt(key, rec)
    return expires ~= nil and expires < now
end

-- Deletes records past their expiry.
function S:PruneExpired()
    self.storeVersion = self.storeVersion + 1
    local now, removed = Now(), 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        if store then
            local dead = {}
            for key, rec in pairs(store) do
                local expires = self:ExpiresAt(key, rec)
                if expires and expires < now then dead[#dead + 1] = key end
            end
            for _, key in ipairs(dead) do
                store[key] = nil
                removed = removed + 1
            end
        end
    end
    if removed > 0 then ns:Fire("RECRUITS_CHANGED") end
    return removed
end

------------------------------------------------------------------------
-- Writing and applying
------------------------------------------------------------------------
-- Changes a record locally and broadcasts it.
-- opts: migration (no audit/broadcast), author, force (skip permission)
function S:Set(key, value, opts)
    opts = opts or {}
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    local typ = S.ParseKey(key)
    if not typ then return nil, "Unknown record." end
    if not opts.force and not self:CanWrite(key) then
        return nil, "Only officers can change that."
    end
    value = Clean(value)
    local store = self:Store(S.TYPES[typ].scope)
    local cur = store[key]
    if cur and cur.v == value then return true end
    local t = opts.time or Now()
    if cur and cur.t >= t then t = cur.t + 1 end
    local rec = { v = value, t = t, a = opts.author or Me() }
    if not opts.migration and not opts.noBatch then rec.b = self:CurrentBatch() end
    self:Apply(key, rec, { origin = "local", migration = opts.migration })
    if not opts.migration then self:QueueOutgoing(key) end
    self:FlushNotify()
    return true
end

------------------------------------------------------------------------
-- Batching: changes made close together are sent (and audited) as one group
------------------------------------------------------------------------
S.outbox = {}

function S:CurrentBatch()
    if not self.batchId then
        self.batchId = Base36(Now()) .. Base36(math.random(0, 46655))
    end
    return self.batchId
end

function S:QueueOutgoing(key)
    self.outbox[key] = true
    if not self.outboxTimer then
        self.outboxTimer = true
        C_Timer.After(self.BATCH_DELAY, function() S:FlushOutgoing() end)
    end
end

-- Sends everything queued, newest version of each record.
function S:FlushOutgoing()
    self.outboxTimer = false
    self.batchId = nil
    local keys = {}
    for key in pairs(self.outbox) do keys[#keys + 1] = key end
    wipe(self.outbox)
    table.sort(keys)
    for _, key in ipairs(keys) do
        local rec = self:Get(key)
        if rec then self:Broadcast(key, rec) end
    end
    return #keys
end

-- Stores a record if it's newer than ours. Returns true when applied.
function S:Apply(key, rec, ctx)
    local typ, member = S.ParseKey(key)
    if not typ then return false end
    local def = S.TYPES[typ]
    local store = self:Store(def.scope)
    if not store then return false end
    rec.t = tonumber(rec.t) or 0
    rec.v = rec.v or ""
    ctx.key = key
    -- recruitment statuses are only kept by members who may recruit
    if ctx.origin == "remote" and typ == "RS" and not self:MayRecruit() then return false end
    if ctx.origin == "remote" and not self:Accept(typ, member, def, rec, ctx) then return false end
    local cur = store[key]
    if cur and not Newer(rec, cur) then return false end
    store[key] = rec
    self.storeVersion = self.storeVersion + 1
    self:Materialize(typ, key, member, rec)
    -- (GS:peonat is only when NGM Peon's code was last brought in: not an audit entry)
    if not def.noAudit and key ~= "GS:peonat" and not ctx.migration and ns.IsOfficer() then
        self:Audit(typ, key, member, cur, rec)
    end
    self.stats.applied = self.stats.applied + 1
    return true
end

------------------------------------------------------------------------
-- Values <-> the addon's working data
------------------------------------------------------------------------
local Codec = {}
S.Codec = Codec

function Codec.ParseSet(v)
    local set = {}
    for id in (v or ""):gmatch("[^,]+") do set[id] = true end
    return set
end

function Codec.Profs(list)
    local parts = {}
    for _, p in ipairs(list or {}) do
        parts[#parts + 1] = ("%s:%d"):format((p.name:gsub("[:,;]", "")), p.rank or 0)
    end
    return table.concat(parts, ",")
end
function Codec.ParseProfs(v)
    local list = {}
    for chunk in (v or ""):gmatch("[^,]+") do
        local name, rank = chunk:match("^([^:]+):?(%d*)$")
        if name then list[#list + 1] = { name = name, rank = tonumber(rank) or 0 } end
    end
    return list
end

-- Addon-reported data: "spec;dist;name:rank:max:icon,..."
function Codec.Report(snap)
    local parts = {}
    for i, p in ipairs(snap.profs or {}) do
        if i > 6 then break end
        parts[#parts + 1] = ("%s:%d:%d:%s"):format((p.name:gsub("[:,;]", "")), p.rank or 0, p.max or 0, p.icon and tostring(p.icon) or "")
    end
    return ("%s;%s;%s"):format(Clean(snap.spec or ""):gsub(";", ""), Clean(snap.dist or ""):gsub(";", ""), table.concat(parts, ","))
end
function Codec.ParseReport(v)
    local spec, dist, profs = (v or ""):match("^([^;]*);([^;]*);(.*)$")
    if not spec then return nil end
    local data = { spec = spec ~= "" and spec or nil, dist = dist ~= "" and dist or nil, profs = {} }
    for chunk in profs:gmatch("[^,]+") do
        local name, rank, max, icon = chunk:match("^([^:]*):(%d*):(%d*):?(%d*)$")
        if name and name ~= "" then
            data.profs[#data.profs + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0, icon = tonumber(icon) }
        end
    end
    return data
end

-- Officer log: "created;creator;text" ("" = deleted)
function Codec.Log(created, creator, text)
    return ("%d;%s;%s"):format(created, Clean(creator):gsub(";", ""), Clean(text))
end
function Codec.ParseLog(v)
    local created, creator, text = (v or ""):match("^(%d+);([^;]*);(.*)$")
    if not created then return nil end
    return { ts = tonumber(created), author = creator, text = text }
end

local pending = { members = {}, links = false, audit = false }

function S:Notify(kind, member)
    if kind == "member" then
        if member then pending.members[member] = true end
    else
        pending[kind] = true
    end
    if not self.notifyQueued then
        self.notifyQueued = true
        C_Timer.After(0.05, function() S:FlushNotify() end)
    end
end

function S:FlushNotify()
    self.notifyQueued = false
    local p = { members = pending.members, links = pending.links, audit = pending.audit }
    pending.members, pending.links, pending.audit = {}, false, false
    if p.links then ns:Fire("LINKS_CHANGED") end
    for member in pairs(p.members) do ns:Fire("MEMBER_CHANGED", member) end
    if p.audit then
        self.auditCache = nil
        ns:Fire("AUDIT_CHANGED")
    end
end

function S:Materialize(typ, key, member, rec)
    local v = rec.v
    if typ == "GS" then
        ns.Debounce("guildsettings", 0.1, function() ns:Fire("GUILD_SETTINGS_CHANGED") end)
        return
    elseif typ == "RP" then
        ns.Debounce("recipeschanged", 0.3, function() ns:Fire("RECIPES_CHANGED") end)
        return
    elseif typ == "HF" or typ == "HX" or typ == "HW" or typ == "HA" or typ == "HC" then
        ns.Debounce("hofchanged", 0.5, function() ns:Fire("HALL_OF_FAME_CHANGED") end)
        return
    elseif typ == "IR" then
        ns.Debounce("reminderschanged", 0.3, function() ns:Fire("MEMBER_CHANGED") end)
        return
    elseif typ == "DN" or typ == "RS" then
        -- Do Not Whisper entries are about people outside the guild: no member record
        ns.Debounce("dnwchanged", 0.1, function() ns:Fire("RECRUITS_CHANGED") end)
        return
    elseif typ == "A" then
        self.auditCache = nil
        self:Notify("audit")
        return
    end
    local m = ns.DB:EnsureMember(member)
    if not m then return end
    if typ == "M" then
        m.main = (v ~= "" and v ~= member) and v or nil
        self:Notify("links")
    elseif typ == "MS" then
        m.spec = v ~= "" and v or nil
    elseif typ == "RL" then
        m.roles = v ~= "" and v or nil
    elseif typ == "MP" then
        local list = Codec.ParseProfs(v)
        m.profs = #list > 0 and list or nil
    elseif typ == "P" then
        local data = v ~= "" and Codec.ParseReport(v) or nil
        if v == "" then m.auto = nil end -- they stopped sharing it
        if data then
            data.ts = rec.t
            m.auto = data
        end
    elseif typ == "CN" then
        m.contact = v ~= "" and v or nil
    elseif typ == "SC" then
        m.schedule = v ~= "" and v or nil
    elseif typ == "AV" then
        m.version = v ~= "" and v or nil
        ns.Debounce("versioncheck", 1, function() if ns.Roster.CheckVersion then ns.Roster:CheckVersion() end end)
    elseif typ == "JN" then
        local t, by = v:match("^(%d+);(.*)$")
        m.joined = t and { t = tonumber(t), by = by ~= "" and by or nil } or nil
    elseif typ == "RK" then
        local t, rank, by = v:match("^(%d+);([^;]*);(.*)$")
        m.rankSince = t and { t = tonumber(t), rank = rank ~= "" and rank or nil, by = by ~= "" and by or nil } or nil
    elseif typ == "L" then
        local id = key:match("^L:[^:]+:(.+)$")
        m.log = m.log or {}
        local entry = Codec.ParseLog(v)
        if entry then
            entry.id, entry.upd = id, rec.t
            m.log[id] = entry
        else
            m.log[id] = { id = id, del = true, upd = rec.t, ts = rec.t, text = "" }
        end
    end
    self:Notify("member", member)
end

-- Rebuilds the working data from records (after loading or migrating).
function S:RebuildAll()
    local g = ns.DB:Guild()
    if not g then return end
    for _, m in pairs(g.members) do
        m.tags, m.main, m.spec, m.profs, m.auto, m.log, m.version = nil, nil, nil, nil, nil, nil, nil
        m.rating = nil
        m.schedule, m.contact = nil, nil
        m.joined, m.rankSince = nil, nil
        m.about, m.status, m.statusAt, m.pronouns = nil, nil, nil, nil
    end
    for _, scope in ipairs({ "guild", "officer" }) do
        for key, rec in pairs(self:Store(scope)) do
            local typ, member = S.ParseKey(key)
            if typ then self:Materialize(typ, key, member, rec) end
        end
    end
    self:FlushNotify()
end

------------------------------------------------------------------------
-- Audit trail
------------------------------------------------------------------------
function S:RetentionSeconds()
    local days = ns.DB:Settings().auditDays or 30
    return days * 86400
end

-- Compact form of a reported-data value for the audit: spec + profession names.
local function ReportSummary(v)
    local d = Codec.ParseReport(v)
    if not d then return "" end
    local names = {}
    for _, p in ipairs(d.profs) do names[#names + 1] = p.name end
    table.sort(names)
    return (d.spec or "") .. ";" .. table.concat(names, ",")
end

function S:Audit(typ, key, member, cur, rec)
    local old = cur and cur.v or ""
    local new = rec.v
    if typ == "P" then
        old, new = cur and ReportSummary(old) or "", ReportSummary(new)
    end
    if old == new then return end
    local store = self:Store("officer")
    -- Same id on every officer's client, so copies of one change merge.
    local id = Base36(Hash(key .. "@" .. rec.t .. "@" .. (rec.a or ""))) .. Base36(rec.t)
    local akey = "A:" .. id
    if store[akey] then return end
    store[akey] = {
        v = table.concat({ member or "", typ, Clean(old), Clean(new), key:sub(#typ + 2), rec.b or "" }, US),
        t = rec.t, a = rec.a or "",
    }
    self.auditCache = nil
    self:Notify("audit")
end

-- Adds an audit entry that isn't about a record (a roster change), and
-- sends it to the other officers. False when it's already there.
function S:AddAuditEntry(id, t, author, member, typ, old, new, ref, batch)
    if not ns.IsOfficer() then return false end
    local store = self:Store("officer")
    if not store then return false end
    local akey = "A:" .. id
    if store[akey] then return false end
    store[akey] = {
        v = table.concat({ member or "", typ, Clean(old), Clean(new), Clean(ref or ""), batch or "" }, US),
        t = math.floor(t), a = author or "",
    }
    self.auditCache = nil
    self:Notify("audit")
    self:QueueOutgoing(akey)
    return true
end

-- Decoded audit entries, newest first: { id, t, author, member, typ, old, new, ref }
function S:AuditEntries()
    if self.auditCache then return self.auditCache end
    local out = {}
    local store = self:Store("officer")
    if store then
        for key, rec in pairs(store) do
            if key:sub(1, 2) == "A:" then
                local f = ns.Split(rec.v, US)
                local member, typ, old, new, ref, batch = f[1], f[2], f[3], f[4], f[5], f[6]
                if typ and typ ~= "" then
                    out[#out + 1] = {
                        id = key:sub(3), t = rec.t, author = rec.a, member = member ~= "" and member or nil,
                        typ = typ, old = old or "", new = new or "", ref = ref,
                        batch = (batch and batch ~= "") and batch or nil,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.id > b.id
    end)
    -- one event-log event noticed an hour apart by two officers: keep one
    local kept, last = {}, {}
    for _, e in ipairs(out) do
        local sig = S.EventSig(e.typ, e.member, e.new)
        if not (sig and last[sig] and last[sig] - e.t <= S.EVENT_DEDUPE) then
            kept[#kept + 1] = e
            if sig then last[sig] = e.t end
        end
    end
    self.auditCache = kept
    return kept
end

function S:PruneAudit()
    local store = self:Store("officer")
    if not store then return end
    local cutoff = Now() - self:RetentionSeconds()
    local removed = 0
    for key, rec in pairs(store) do
        if key:sub(1, 2) == "A:" and rec.t < cutoff then
            store[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        self.auditCache = nil
        ns:Fire("AUDIT_CHANGED")
    end
    return removed
end

-- Deletes stored records of types this version no longer has (reviews,
-- ratings, map dot colors, polls, stats, goals, kudos, About me, status,
-- pronouns), and retired guild settings (tab titles and ranks, pronouns), so
-- they don't linger in the saved data.
function S:PurgeUnknown()
    local removed = 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        if store then
            local dead = {}
            for key, rec in pairs(store) do
                if not S.ParseKey(key) or key:match("^GS:tab_") or key == "GS:pronouns" or key == "GS:reviews"
                    or key == "GS:perm_tags" or key == "GS:perm_tagothers" or key == "GS:perm_recruit" then
                    dead[#dead + 1] = key
                elseif key:sub(1, 2) == "A:" then
                    -- audit entries about removed types
                    local typ = ns.Split(rec.v or "", US)[2]
                    if typ and typ ~= "" and not S.TYPES[typ] and not S.ROSTER_EVENTS[typ] then dead[#dead + 1] = key end
                end
            end
            for _, key in ipairs(dead) do store[key] = nil end
            removed = removed + #dead
        end
    end
    if removed > 0 then self.auditCache = nil end
    return removed
end
