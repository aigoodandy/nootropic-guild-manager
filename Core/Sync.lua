--[[
    Nootropic Guild Manager - Sync engine (protocol 2)

    Shared data is stored as RECORDS: key -> { v = value, t = time, a = author }.
    Every change gets the server time and its author, and the newest version of
    a record always wins (ties broken by author name), so every copy converges
    on the same data no matter what order messages arrive in.

    Scopes
      guild    tags, tag assignments, main/alt links, specs and professions.
               Sent on the GUILD addon channel.
      officer  ratings, officer log, audit trail. Sent only on the OFFICER
               addon channel (the game delivers it only to ranks that can read
               officer chat). Nothing is ever whispered.

    Delivery
      1. Batches: local changes apply instantly but are sent together 15
         seconds after the first one (one BATCH id, also used to group the
         audit trail).
      2. Repair: clients regularly broadcast a DIGEST (16 checksums over all
         their records). Anyone whose checksums differ re-broadcasts just the
         mismatched buckets on the same channel (never by whisper), announced
         with a B marker so other clients don't send the same bucket again.
         Lost messages, offline officers and late joiners all heal this way.
      3. Transport: a byte-budget queue (live changes first), retries when the
         game reports throttling or combat lockdown, and splits long messages.

    Record keys
      T:<tagId>            tag definition          officers
      MT:<member>          member's tags           officers, or the member
      M:<member>           member's main ("" = main) officers
      MS:<member>          spec override           officers, or the member
      MP:<member>          manual professions      officers, or the member
      P:<member>           addon-reported spec/professions   the member only
      RT:<member>          rating 0-5              officers (officer scope)
      L:<member>:<id>      officer log entry       officers (officer scope)
      A:<id>               audit entry             officers (officer scope)
      DN:<player>          Do Not Whisper entry    anyone in the guild ("" = removed)
      RS:<player>          recruitment status      anyone in the guild (kept 7 days)
      DC:<member>          map dot colors          the member only
      AV:<member>          addon version in use    the member only
      GR:<id>              anonymous guild review  officers (officer scope, kept 1 year,
                                                   no author, can never be changed or deleted)
      GC:<review>:<id>     officer comment on a review   officers (kept 1 year)
      TI:<tagId>           tag icon (file id or texture path)   officers
      GS:<name>            guild-wide setting, e.g. GS:reviews = "0" (off)   officers
      PL:<id>              poll (question, options, close time)   officers
                           kept until its results expire
      PV:<poll>:<member>   a member's vote in a poll   the member only
                           (only counted if cast before the poll closed)
      AB:<member>          About me text            the member; officers may only clear it ("")
      ST:<member>          status line              the member only
      PN:<member>          pronouns (shown only while GS:pronouns = "1")
                           the member; officers may only clear it ("")
      SC:<member>          usual online hours: 168 bits (Monday 00:00 UTC
                           onward) as 42 hex digits   the member only
      KT:<id>              kudos type (like a tag definition)   officers
      PI:<pollId>          each answer's color and icon: "o;1=color:icon~2=..."   officers
      SD:<id>              guild stat everyone sees:
                           "v3;group;deleted;title;looks;filter" (looks: each
                           row's color and icon, "Mage=8:icon~...")   officers
      SO:<id>              custom stat only officers see (officer scope), same value   officers
      KD:<id>              kudos description (tooltip text; none = the
                           default kudos' own text)   officers
      KU:<member>:<type>:<id>  one anonymous kudos for <member>: no author,
                           random id, kept 90 days   anyone in the guild

    Types with a ttl (or an expires function) expire: older records are
    deleted, left out of digests and repairs, and refused when they arrive.
]]
local _, ns = ...
local S = {}
ns.Sync = S

local PREFIX = "NootropicGM"
local PROTO = "3" -- 3: batches, channel-only repair
S.PROTO = PROTO
S.FS = "\t"
local FS = "\t"
local US = "\031" -- separator inside audit values

S.BUCKETS = 16
S.AUDIT_SYNC_WINDOW = 30 * 86400 -- audit older than this isn't compared (retention differs per officer)
S.DIGEST_INTERVAL = 600          -- routine digest every 10 minutes
S.EXCHANGE_COOLDOWN = 120        -- at most one routine exchange every 2 minutes
S.BATCH_DELAY = 15               -- local changes are sent together after this many seconds
S.DUMP_SUPPRESS = 60             -- don't re-send a bucket someone just re-sent
S.BYTES_PER_SEC = 600            -- gentler than ChatThrottleLib's 800
S.BURST = 1800
S.CHUNK = 200
S.MAX_MSG = 250

S.TYPES = {
    T  = { scope = "guild",   officer = true, label = "Tag" },
    MT = { scope = "guild",   officer = true, self = true, label = "Tags" },
    M  = { scope = "guild",   officer = true, label = "Main / Alt" },
    MS = { scope = "guild",   officer = true, self = true, label = "Spec" },
    MP = { scope = "guild",   officer = true, self = true, label = "Professions" },
    P  = { scope = "guild",   selfOnly = true, label = "Reported spec / professions" },
    RT = { scope = "officer", officer = true, label = "Rating" },
    L  = { scope = "officer", officer = true, label = "Officer log" },
    A  = { scope = "officer", officer = true, noAudit = true, label = "Audit" },
    DN = { scope = "guild",   anyone = true, label = "Do Not Whisper" },
    RS = { scope = "guild",   anyone = true, noAudit = true, ttl = 7 * 86400, label = "Recruitment status" },
    DC = { scope = "guild",   selfOnly = true, noAudit = true, label = "Map dot colors" },
    AV = { scope = "guild",   selfOnly = true, noAudit = true, label = "Addon version" },
    GR = { scope = "officer", officer = true, noAudit = true, ttl = 365 * 86400, low = true, immutable = true, anonymous = true, label = "Guild review" },
    GC = { scope = "officer", officer = true, noAudit = true, ttl = 365 * 86400, low = true, label = "Review comment" },
    TI = { scope = "guild",   officer = true, label = "Tag icon" },
    GS = { scope = "guild",   officer = true, label = "Guild setting" },
    PL = { scope = "guild",   officer = true, label = "Poll" },
    PV = { scope = "guild",   selfOnly = true, noAudit = true, label = "Poll vote" },
    AB = { scope = "guild",   officer = true, self = true, label = "About me" },
    ST = { scope = "guild",   selfOnly = true, noAudit = true, label = "Status" },
    PN = { scope = "guild",   officer = true, self = true, label = "Pronouns" },
    SC = { scope = "guild",   selfOnly = true, noAudit = true, label = "Usually online" },
    KT = { scope = "guild",   officer = true, label = "Kudos type" },
    KD = { scope = "guild",   officer = true, label = "Kudos description" },
    PI = { scope = "guild",   officer = true, label = "Poll look" },
    SD = { scope = "guild",   officer = true, label = "Guild stat" },
    SO = { scope = "officer", officer = true, label = "Officer stat" },
    KU = { scope = "guild",   anyone = true, noAudit = true, ttl = 90 * 86400, low = true, immutable = true, anonymous = true, label = "Kudos" },
}
local CHANNEL = { guild = "GUILD", officer = "OFFICER" }
-- Types whose key is not about one member.
local NO_MEMBER = { T = true, A = true, GR = true, GC = true, TI = true, GS = true, PL = true, KT = true, KD = true, SD = true, SO = true, PI = true }

-- Orphaned poll votes (their poll is unknown) are kept this long.
local ORPHAN_VOTE_TTL = 30 * 86400

S.officers = {} -- players seen sending on the officer channel this session
S.officerBeacons = {} -- officers running the addon -> GetTime() they last said so
S.stats = { sent = 0, received = 0, applied = 0, retries = 0, dropped = 0 }

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
    if typ == "L" or typ == "KU" then
        member = rest:match("^([^:]+):")
    elseif typ == "PV" then
        member = rest:match("^[^:]+:(.+)$")
        if not member then return nil end
    elseif not NO_MEMBER[typ] then
        member = rest
    end
    return typ, member, rest
end

-- When a record stops being kept (server time), or nil when it never expires.
-- Polls are kept until their results expire; votes go with their poll.
function S:ExpiresAt(key, rec)
    local typ, _, rest = S.ParseKey(key)
    if not typ then return nil end
    if typ == "PL" then
        local p = S.Codec.ParsePoll(rec.v)
        return p and p.expireAt or rec.t + ORPHAN_VOTE_TTL
    elseif typ == "PV" then
        local poll = self:Get("PL:" .. rest:match("^([^:]+):"))
        local p = poll and S.Codec.ParsePoll(poll.v)
        return p and p.expireAt or rec.t + ORPHAN_VOTE_TTL
    end
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
    local typ, member = S.ParseKey(key)
    if not typ then return false end
    local def = S.TYPES[typ]
    if def.selfOnly then return member == Me() end
    if def.anyone then return IsInGuild() end
    if def.officer and ns.IsOfficer() then return true end
    if def.self and member == Me() then return true end
    return false
end

-- Should we accept this record from someone else?
function S:Accept(typ, member, def, rec, ctx)
    if def.scope == "officer" then
        -- the game only delivers the officer channel to officer ranks
        if ctx.channel ~= "OFFICER" or not ns.IsOfficer() then return false end
    elseif ctx.channel ~= "GUILD" then
        return false
    end
    if def.selfOnly and rec.a ~= member then return false end
    if rec.t > Now() + 300 then return false end -- refuse timestamps from the future
    if typ == "A" and rec.t < Now() - self:RetentionSeconds() then return false end
    local expires = self:ExpiresAt(ctx.key, rec)
    if expires and expires < Now() then return false end
    if def.anonymous and (rec.a or "") ~= "" then return false end -- reviews never carry a name
    if typ == "PV" and not self:VoteInTime(ctx.key, rec) then return false end
    -- someone else's About me or pronouns can only be cleared (officers), never rewritten
    if (typ == "AB" or typ == "PN") and rec.a ~= member and rec.v ~= "" then return false end
    return true
end

-- A vote counts only if it was cast before its poll closed (a minute of
-- slack for clock differences). Votes for polls we don't know yet pass.
function S:VoteInTime(key, rec)
    local pollId = key:match("^PV:([^:]+):")
    local poll = pollId and self:Get("PL:" .. pollId)
    local p = poll and S.Codec.ParsePoll(poll.v)
    if not p then return true end
    return not p.deleted and rec.t <= p.closeAt + 60
end

-- Records left out of digests and repairs: old audit entries (each officer
-- keeps a different amount) and anything past its expiry.
function S:Excluded(key, rec, now)
    now = now or Now()
    if key:sub(1, 2) == "A:" then return rec.t < now - self.AUDIT_SYNC_WINDOW end
    local expires = self:ExpiresAt(key, rec)
    return expires ~= nil and expires < now
end

-- Deletes records past their expiry.
function S:PruneExpired()
    local now, removed, polls = Now(), 0, false
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        if store then
            -- collect first: a vote's expiry depends on its poll record
            local dead = {}
            for key, rec in pairs(store) do
                local expires = self:ExpiresAt(key, rec)
                if expires and expires < now then dead[#dead + 1] = key end
            end
            for _, key in ipairs(dead) do
                store[key] = nil
                removed = removed + 1
                if key:sub(1, 1) == "P" and key:sub(3, 3) == ":" then polls = true end
            end
        end
    end
    if removed > 0 then ns:Fire("RECRUITS_CHANGED") end
    if polls then ns:Fire("POLLS_CHANGED") end
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

function S:PendingCount()
    local n = 0
    for _ in pairs(self.outbox) do n = n + 1 end
    return n
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
    if ctx.origin == "remote" and not self:Accept(typ, member, def, rec, ctx) then return false end
    local cur = store[key]
    if cur and not Newer(rec, cur) then return false end
    if cur and def.immutable then return false end -- reviews can't be changed or deleted
    -- a comment can only be changed (or deleted) by the officer who wrote it
    if cur and typ == "GC" and ctx.origin == "remote" and (cur.a or "") ~= (rec.a or "") then return false end
    store[key] = rec
    self:Materialize(typ, key, member, rec)
    if not def.noAudit and not ctx.migration and ns.IsOfficer() then
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

function Codec.TagDef(color, order, deleted, name)
    return ("%d;%s;%d;%s"):format(color or 1, tostring(order or 0), deleted and 1 or 0, Clean(name))
end
function Codec.ParseTagDef(v)
    local color, order, del, name = (v or ""):match("^(%d+);([%d%.%-]+);(%d);(.*)$")
    if not color then return nil end
    return { color = tonumber(color), order = tonumber(order) or 0, deleted = del == "1", name = name }
end

function Codec.Set(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    return table.concat(ids, ",")
end
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

-- Kudos type: "color;order;retired;icon;name"
function Codec.KudosType(color, order, retired, icon, name)
    return ("%d;%s;%d;%s;%s"):format(color or 1, tostring(order or 0), retired and 1 or 0,
        (Clean(icon or ""):gsub(";", "")), Clean(name))
end
function Codec.ParseKudosType(v)
    local color, order, retired, icon, name = (v or ""):match("^(%d+);([%d%.%-]+);(%d);([^;]*);(.*)$")
    if not color then return nil end
    return { color = tonumber(color), order = tonumber(order) or 0, retired = retired == "1",
        icon = ns.Data:ParseIcon(icon), name = name }
end

-- Row looks: a color and icon for each row of a stat ("Mage") or answer of
-- a poll ("1"): { [label] = { color = n or nil, icon = icon, false (show
-- none) or nil (the row's own) } }, written as "label=color:icon~...":
-- color 0 = the row's own, icon "-" = none, "" = the row's own.
local function LookLabel(s) return (Clean(s or ""):gsub("[~=;]", "")) end
function Codec.Looks(looks)
    local parts = {}
    for label, l in pairs(looks or {}) do
        local icon = l.icon == false and "-" or (Clean(l.icon or ""):gsub("[~;:]", ""))
        parts[#parts + 1] = ("%s=%d:%s"):format(LookLabel(label), tonumber(l.color) or 0, icon)
    end
    table.sort(parts)
    return table.concat(parts, "~")
end
function Codec.ParseLooks(v)
    local out = {}
    for entry in (v or ""):gmatch("[^~]+") do
        local label, color, icon = entry:match("^([^=]*)=(%d+):(.*)$")
        if label then
            color = tonumber(color)
            local parsed
            if icon == "-" then parsed = false elseif icon ~= "" then parsed = ns.Data:ParseIcon(icon) end
            out[label] = { color = color ~= 0 and color or nil, icon = parsed }
        end
    end
    return out
end
Codec.LookLabel = LookLabel

-- Stat: "v3;group;deleted;title;looks;filter" (the filter is a roster
-- search and may itself contain ";"). Earlier 1.13 betas wrote
-- "v2;group;deleted;color;icon;title;filter" and "group;deleted;title;filter",
-- still read.  s: { group, deleted, title, looks, filter }
function Codec.CustomStat(s)
    return ("v3;%s;%d;%s;%s;%s"):format((Clean(s.group or ""):gsub(";", "")), s.deleted and 1 or 0,
        (Clean(s.title or ""):gsub(";", ",")), Codec.Looks(s.looks), Clean(s.filter or ""))
end
function Codec.ParseCustomStat(v)
    v = v or ""
    local group, deleted, title, looks, filter = v:match("^v3;([^;]*);(%d);([^;]*);([^;]*);(.*)$")
    if not group then
        group, deleted, title, filter = v:match("^v2;([^;]*);(%d);%d+;[^;]*;([^;]*);(.*)$")
    end
    if not group then
        group, deleted, title, filter = v:match("^([^;]*);(%d);([^;]*);(.*)$")
        if not group then return nil end
    end
    return { group = group, deleted = deleted == "1", title = title, looks = Codec.ParseLooks(looks), filter = filter }
end

-- Poll answer looks (PI:<pollId>): "o;" .. looks keyed by answer number.
-- (An early beta wrote "color;icon" for the whole poll; ignored.)
function Codec.PollLooks(looks)
    return "o;" .. Codec.Looks(looks)
end
function Codec.ParsePollLooks(v)
    local rest = (v or ""):match("^o;(.*)$")
    return rest and Codec.ParseLooks(rest) or {}
end

-- Poll: "closeAt;expireAt;deleted;question;option1;option2;..."
local function PollText(s) return (Clean(s):gsub(";", ",")) end
function Codec.Poll(p)
    local parts = { tostring(math.floor(p.closeAt)), tostring(math.floor(p.expireAt)), p.deleted and "1" or "0", PollText(p.question) }
    for _, o in ipairs(p.options) do parts[#parts + 1] = PollText(o) end
    return table.concat(parts, ";")
end
function Codec.ParsePoll(v)
    local f = ns.Split(v or "", ";")
    local closeAt, expireAt = tonumber(f[1]), tonumber(f[2])
    if not (closeAt and expireAt and f[4]) then return nil end
    local p = { closeAt = closeAt, expireAt = expireAt, deleted = f[3] == "1", question = f[4], options = {} }
    for i = 5, #f do p.options[#p.options + 1] = f[i] end
    return p
end

local pending = { members = {}, tags = false, links = false, audit = false }

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
    local p = { members = pending.members, tags = pending.tags, links = pending.links, audit = pending.audit }
    pending.members, pending.tags, pending.links, pending.audit = {}, false, false, false
    if p.tags then
        ns.DB:InvalidateTags()
        ns:Fire("TAGS_CHANGED") -- redecorates everyone
    end
    if p.links then ns:Fire("LINKS_CHANGED") end
    if not p.tags then
        for member in pairs(p.members) do ns:Fire("MEMBER_CHANGED", member) end
    end
    if p.audit then
        self.auditCache = nil
        ns:Fire("AUDIT_CHANGED")
    end
end

function S:Materialize(typ, key, member, rec)
    local v = rec.v
    if typ == "T" or typ == "TI" then
        self:Notify("tags")
        return
    elseif typ == "PL" or typ == "PV" or typ == "PI" then
        ns.Debounce("pollschanged", 0.2, function() ns:Fire("POLLS_CHANGED") end)
        return
    elseif typ == "GS" then
        ns.Debounce("guildsettings", 0.1, function() ns:Fire("GUILD_SETTINGS_CHANGED") end)
        return
    elseif typ == "SD" or typ == "SO" then
        ns.Debounce("statschanged", 0.2, function() ns:Fire("STATS_CHANGED") end)
        return
    elseif typ == "KT" or typ == "KD" or typ == "KU" then
        if typ == "KU" then ns.Profile:InvalidateKudosIndex() else ns.DB.kudosCache = nil end
        ns.Debounce("kudoschanged", 0.2, function() ns:Fire("KUDOS_CHANGED") end)
        return
    elseif typ == "GR" or typ == "GC" then
        ns.Debounce("reviewschanged", 0.2, function() ns:Fire("REVIEWS_CHANGED") end)
        return
    elseif typ == "DC" then
        ns.Debounce("dotcolors", 0.2, function() ns:Fire("LOCATIONS_CHANGED") end)
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
    if typ == "MT" then
        m.tags = Codec.ParseSet(v)
    elseif typ == "M" then
        m.main = (v ~= "" and v ~= member) and v or nil
        self:Notify("links")
    elseif typ == "MS" then
        m.spec = v ~= "" and v or nil
    elseif typ == "MP" then
        local list = Codec.ParseProfs(v)
        m.profs = #list > 0 and list or nil
    elseif typ == "P" then
        local data = Codec.ParseReport(v)
        if data then
            data.ts = rec.t
            m.auto = data
        end
    elseif typ == "AB" then
        m.about = v ~= "" and v or nil
    elseif typ == "ST" then
        m.status, m.statusAt = (v ~= "" and v or nil), rec.t
    elseif typ == "PN" then
        m.pronouns = v ~= "" and v or nil
    elseif typ == "SC" then
        m.schedule = v ~= "" and v or nil
    elseif typ == "AV" then
        m.version = v ~= "" and v or nil
        ns.Debounce("versioncheck", 1, function() if ns.Roster.CheckVersion then ns.Roster:CheckVersion() end end)
    elseif typ == "RT" then
        m.rating = math.max(0, math.min(5, tonumber(v) or 0))
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
        m.tags, m.main, m.spec, m.profs, m.auto, m.rating, m.log, m.version = {}, nil, nil, nil, nil, 0, nil, nil
        m.about, m.status, m.statusAt, m.schedule = nil, nil, nil, nil
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
    self.auditCache = out
    return out
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

------------------------------------------------------------------------
-- Digests (repair)
------------------------------------------------------------------------
local function Bucket(key) return Hash(key) % S.BUCKETS + 1 end

function S:Digest(scope)
    local sums = {}
    for i = 1, self.BUCKETS do sums[i] = 0 end
    local store = self:Store(scope)
    if not store then return sums end
    local now = Now()
    for key, rec in pairs(store) do
        if not self:Excluded(key, rec, now) then
            local b = Bucket(key)
            -- the value is included so same-time copies with different contents still get reconciled
            sums[b] = (sums[b] + Hash(key .. FS .. rec.t .. FS .. (rec.a or "") .. FS .. (rec.v or ""))) % 4294967291
        end
    end
    return sums
end

local function EncodeDigest(sums)
    local parts = {}
    for i, s in ipairs(sums) do parts[i] = Base36(s) end
    return table.concat(parts, ",")
end

local function DecodeDigest(str)
    local sums = {}
    for part in (str or ""):gmatch("[^,]+") do sums[#sums + 1] = tonumber(part, 36) or -1 end
    return sums
end

-- Broadcast our digests so peers can tell us what we're missing (and vice versa).
function S:Exchange(force)
    if not IsInGuild() or not ns.DB:Guild() then return false end
    local now = GetTime()
    local since = now - (self.lastExchange or -1e9)
    if since < (force and 10 or self.EXCHANGE_COOLDOWN) then return false end
    self.lastExchange = now
    self:Send(table.concat({ PROTO, "D", "guild", EncodeDigest(self:Digest("guild")) }, FS), "GUILD", nil, "high")
    if ns.IsOfficer() then
        self:Send(table.concat({ PROTO, "O" }, FS), "GUILD", nil, "bulk")
        self:Send(table.concat({ PROTO, "D", "officer", EncodeDigest(self:Digest("officer")) }, FS), "OFFICER", nil, "high")
    end
    return true
end

S.dumped = { guild = {}, officer = {} } -- bucket -> GetTime() someone last re-sent it

function S:OnDigest(scope, digest, sender, channel)
    if scope == "officer" then
        if channel ~= "OFFICER" or not ns.IsOfficer() then return end
    elseif scope ~= "guild" or channel ~= "GUILD" then
        return
    end
    local theirs = DecodeDigest(digest)
    local diff = self:DiffBuckets(scope, theirs)
    if #diff == 0 then return end
    -- A short random wait, so when several clients notice the same gap only
    -- the first one re-sends it (the others see its B marker and skip).
    C_Timer.After(2 + math.random() * 6, function()
        local still = S:DiffBuckets(scope, theirs, diff)
        local now = GetTime()
        local send = {}
        for _, b in ipairs(still) do
            if now - (S.dumped[scope][b] or -1e9) > S.DUMP_SUPPRESS then send[#send + 1] = b end
        end
        if #send > 0 then S:SendBuckets(scope, send) end
        -- they may have newer data than us: let them compare against ours
        S:Exchange(true)
    end)
end

function S:DiffBuckets(scope, theirs, only)
    local mine = self:Digest(scope)
    local out = {}
    local list = only
    if not list then
        list = {}
        for i = 1, self.BUCKETS do list[i] = i end
    end
    for _, b in ipairs(list) do
        if mine[b] ~= theirs[b] then out[#out + 1] = b end
    end
    return out
end

-- Re-broadcasts every record in the given buckets on the scope's channel.
function S:SendBuckets(scope, buckets)
    local store = self:Store(scope)
    if not store then return end
    if scope == "officer" and not ns.IsOfficer() then return end
    local channel = CHANNEL[scope]
    local want = {}
    local now = GetTime()
    for _, b in ipairs(buckets) do
        want[b] = true
        self.dumped[scope][b] = now
        self:Send(table.concat({ PROTO, "B", scope, tostring(b) }, FS), channel, nil, "bulk")
    end
    local now = Now()
    for key, rec in pairs(store) do
        if want[Bucket(key)] and not self:Excluded(key, rec, now) then
            self:Send(self:EncodeRecord(key, rec), channel, nil, "bulk")
        end
    end
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
function S:EncodeRecord(key, rec)
    return table.concat({ PROTO, "R", key, tostring(rec.t), rec.a or "", rec.b or "", rec.v or "" }, FS)
end

function S:Broadcast(key, rec)
    local typ = S.ParseKey(key)
    local def = S.TYPES[typ]
    local scope = def.scope
    if scope == "officer" and not ns.IsOfficer() then return end
    self:Send(self:EncodeRecord(key, rec), CHANNEL[scope], nil, def.low and "bulk" or "high")
end

local partials = {}

function S:OnMessage(msg, channel, sender)
    local who = ns.NormalizeName(sender)
    if not who or who == Me() then return end
    if channel == "OFFICER" then self.officers[who] = true end
    local f = ns.Split(msg, FS)
    if f[1] ~= PROTO then return end -- other protocol versions are ignored
    self.stats.received = self.stats.received + 1
    ns.Count("bytesIn", #msg)
    local kind = f[2]
    if kind == "R" then
        local key, t, author, batch = f[3], tonumber(f[4]), f[5], f[6]
        if not key or not t then return end
        local value = table.concat(f, FS, 7)
        local rec = { v = value, t = t, a = author, b = (batch ~= "" and batch) or nil }
        self:Apply(key, rec, { origin = "remote", channel = channel, sender = who })
        self:Notify("member") -- schedule a flush
    elseif kind == "D" then
        self:OnDigest(f[3], f[4], who, channel)
    elseif kind == "P" then
        -- live position for the world map (not stored, not audited)
        if channel == "GUILD" and ns.Location then ns.Location:OnPosition(who, f[3], f[4], f[5]) end
    elseif kind == "O" then
        -- an officer running the addon is online (reviews are handed to one)
        if channel == "GUILD" then self.officerBeacons[who] = GetTime() end
    elseif kind == "V" or kind == "K" then
        -- a review handed to an officer, or an officer confirming it arrived
        if channel == "WHISPER" and ns.Reviews then ns.Reviews:OnMessage(kind, f, who) end
    elseif kind == "B" then
        local scope, b = f[3], tonumber(f[4])
        if b and self.dumped[scope] then self.dumped[scope][b] = GetTime() end
    elseif kind == "C" then
        -- chunk: id, index, total, data
        local id, i, n = f[3], tonumber(f[4]), tonumber(f[5])
        if not (id and i and n) then return end
        local pkey = who .. ":" .. id
        local p = partials[pkey]
        if not p then
            p = { parts = {}, count = 0, n = n, at = GetTime() }
            partials[pkey] = p
        end
        if not p.parts[i] then
            p.parts[i] = table.concat(f, FS, 6)
            p.count = p.count + 1
        end
        if p.count == p.n then
            partials[pkey] = nil
            self:OnMessage(table.concat(p.parts), channel, sender)
        end
        -- forget stale partial messages
        for k, v in pairs(partials) do
            if GetTime() - v.at > 60 then partials[k] = nil end
        end
    end
end

------------------------------------------------------------------------
-- Transport: byte budget, priorities, retries, chunking
------------------------------------------------------------------------
local queues = { high = {}, bulk = {} }
local tokens, lastRefill = nil, nil
local chunkId = 0
S.queues = queues

local RESULT_RETRY = { [3] = 1, [8] = 1, [11] = 5 } -- throttle, channel throttle, combat lockdown (seconds)

local function RawSend(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then return "drop" end
    local ok, res = pcall(send, PREFIX, msg, channel, target)
    if not ok then return "drop" end
    if res == nil or res == true or res == 0 then return "ok" end
    if type(res) == "number" and RESULT_RETRY[res] then return "retry", RESULT_RETRY[res] end
    return "drop"
end

function S:Send(msg, channel, target, prio)
    local q = queues[prio or "high"]
    if #msg > self.MAX_MSG then
        chunkId = (chunkId + 1) % 46656
        local id = Base36(chunkId)
        local n = math.ceil(#msg / self.CHUNK)
        for i = 1, n do
            local part = msg:sub((i - 1) * self.CHUNK + 1, i * self.CHUNK)
            q[#q + 1] = { table.concat({ PROTO, "C", id, tostring(i), tostring(n), part }, FS), channel, target }
        end
    else
        q[#q + 1] = { msg, channel, target }
    end
    self:Pump()
end

function S:Pump()
    if self.pumping then return end
    self.pumping = true
    local function step()
        local now = GetTime()
        tokens = tokens or self.BURST
        lastRefill = lastRefill or now
        tokens = math.min(self.BURST, tokens + (now - lastRefill) * self.BYTES_PER_SEC)
        lastRefill = now
        while true do
            local q = (#queues.high > 0 and queues.high) or (#queues.bulk > 0 and queues.bulk)
            if not q then
                S.pumping = false
                return
            end
            local item = q[1]
            local cost = #item[1] + #PREFIX + 10
            if tokens < cost then break end
            local result, wait = RawSend(item[1], item[2], item[3])
            if result == "retry" then
                S.stats.retries = S.stats.retries + 1
                C_Timer.After(wait, step)
                return
            end
            table.remove(q, 1)
            tokens = tokens - cost
            if result == "ok" then
                S.stats.sent = S.stats.sent + 1
                ns.Count("bytesOut", cost)
            else
                S.stats.dropped = S.stats.dropped + 1
            end
        end
        C_Timer.After(0.25, step)
    end
    step()
end

function S:QueueSize()
    return #queues.high + #queues.bulk
end

------------------------------------------------------------------------
-- Migration from the old (protocol 1) data
------------------------------------------------------------------------
local function TagIdFor(name)
    for i, def in ipairs(ns.Data.DEFAULT_TAGS) do
        if def[1]:lower() == name:lower() then return "d" .. i end
    end
    return "c" .. Base36(Hash(name:lower())) -- stable for the same name on every client
end

-- Default tag records are identical on every client (time 1, no author).
function S:SeedDefaults()
    local store = self:Store("guild")
    for i, def in ipairs(ns.Data.DEFAULT_TAGS) do
        local key = "T:d" .. i
        if not store[key] then
            store[key] = { v = Codec.TagDef(def[2], i * 10, false, def[1]), t = 1, a = "" }
        end
    end
    -- default guild stats, the same way (time 3: replaces an untouched
    -- default from an earlier beta, which were times 1 and 2)
    for i, def in ipairs(ns.Stats.DEFAULTS) do
        local key = "SD:d" .. i
        local v = Codec.CustomStat({ title = def[1], group = def[2] })
        local cur = store[key]
        if not cur or (cur.t < 3 and (cur.a or "") == "") then
            store[key] = { v = v, t = 3, a = "" }
        end
    end
    -- default kudos, the same way (identical everywhere, so they never conflict)
    for i, def in ipairs(ns.Data.DEFAULT_KUDOS) do
        local key = "KT:d" .. i
        if not store[key] then
            store[key] = { v = Codec.KudosType(def[2], i * 10, false, def[3], def[1]), t = 1, a = "" }
        end
    end
end

function S:Migrate()
    local g = ns.DB:Guild()
    if not g or g.syncVersion == 2 then return end
    local me = Me()
    local store = self:Store("guild")
    local officerStore = self:Store("officer")

    -- Tags: old numeric ids -> stable string ids
    local idMap = {}
    for i, tag in ipairs(g.tags or {}) do
        if type(tag) == "table" and tag.name then
            local newId = TagIdFor(tag.name)
            idMap[tag.id] = newId
            local key = "T:" .. newId
            if not store[key] then
                store[key] = { v = Codec.TagDef(tag.color, i * 10, false, tag.name), t = 1, a = me }
            end
        end
    end
    self:SeedDefaults()

    for full, m in pairs(g.members or {}) do
        if type(m) == "table" then
            local set = {}
            for oldId, on in pairs(m.tags or {}) do
                if on and idMap[oldId] then set[idMap[oldId]] = true end
            end
            if next(set) then store["MT:" .. full] = { v = Codec.Set(set), t = 1, a = me } end
            if m.main then store["M:" .. full] = { v = m.main, t = 1, a = me } end
            if m.spec then store["MS:" .. full] = { v = Clean(m.spec), t = 1, a = me } end
            if m.profs and #m.profs > 0 then store["MP:" .. full] = { v = Codec.Profs(m.profs), t = 1, a = me } end
            if m.auto then store["P:" .. full] = { v = Codec.Report(m.auto), t = m.auto.ts or 1, a = full } end
            if m.rating and m.rating > 0 then officerStore["RT:" .. full] = { v = tostring(m.rating), t = 1, a = me } end
            for id, e in pairs(m.log or {}) do
                local key = "L:" .. full .. ":" .. id
                if e.del then
                    officerStore[key] = { v = "", t = e.upd or e.ts or 1, a = me }
                else
                    officerStore[key] = { v = Codec.Log(e.ts or 1, e.author or "?", e.text or ""), t = e.upd or e.ts or 1, a = me }
                end
            end
        end
    end
    g.tags, g.nextTagId, g.logUpd = nil, nil, nil
    g.syncVersion = 2
    self.migrated = true
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function S:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
    ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
        if prefix == PREFIX then S:OnMessage(msg, channel, sender) end
    end)

    -- Guild data arrives a little after login; prepare once it's there.
    local function ready()
        local key = ns.DB:GuildKey()
        if not key or S.readyFor == key or not ns.DB:Guild() then return end
        S.readyFor = key
        S:Migrate()
        S:SeedDefaults()
        S:PruneAudit()
        S:PruneExpired()
        S:RebuildAll()
        -- tell the guild which version of the addon we run
        S:Set("AV:" .. Me(), ns.version)
        C_Timer.After(5 + math.random() * 10, function() S:Exchange(true) end)
    end
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", ready)
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", ready)
    ready()

    -- the roster spells your name differently than expected: re-announce
    -- your version (and spec/professions) under that spelling
    ns:On("SELF_NAME_CHANGED", function()
        if not S.readyFor then return end
        S:Set("AV:" .. Me(), ns.version)
        if ns.Comm then ns.Comm:Report() end
    end)

    -- flush queued changes when the player logs out or reloads (best effort;
    -- anything missed is repaired by the next digest exchange)
    ns:RegisterEvent("PLAYER_LOGOUT", function() S:FlushOutgoing() end)

    local function tick()
        S:PruneExpired()
        S:Exchange(false)
        C_Timer.After(S.DIGEST_INTERVAL, tick)
    end
    C_Timer.After(S.DIGEST_INTERVAL, tick)
end
