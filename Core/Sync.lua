--[[
    Nootropic Guild Manager - Sync (protocol 6)

    Carries records (Core/Records.lua) between guildmates in game. Lean by
    design: nothing is sent while nothing changes.

      Live changes   A change is sent once, bundled with others made in the
                     same 15 seconds, compressed when that's smaller.
      Checks         At login (and on /ngm sync) a copy sends one
                     fingerprint per lane. One guildmate answers, chosen the
                     same way by every copy. If the fingerprints match, that's
                     it. If not: 32 group fingerprints, then per-author lists
                     for the groups that differ, then each side asks for
                     exactly the authors it's behind on.
      Answers        Asked of the author when they're online (everyone
                     answers for their own records), otherwise of an officer
                     chosen per author, so the work is spread out. Sent as
                     compressed bundles to the whole channel, so everyone who
                     was missing them gets them too.
      Dead guild     Rarely the game accepts someone's guild addon messages
      channel        and delivers them to nobody. Every guild message normally
                     comes back to its sender; a copy that hears none back
                     whispers one online officer instead, who passes on that
                     member's own records (only theirs).

    Messages (fields tab-separated, all start with PROTO):
      R  key time author batch value          one record
      B  lane z data                          records bundle, Base64(Deflate(lines))
      F  lane root q|a target [groups]        fingerprint: q asks, a answers
      E  lane target 1|2 groups entries       per-author list: author:newest:sum
      Q  lane target author:since,...         "send these authors' records newer than since"
      H  / K                                  relay hello / its acknowledgement (whispers)
      C  id part parts data                   a piece of a longer message
    Only the GUILD and OFFICER channels are read, plus whispers from
    guildmates to an officer acting as relay. Copies before 2.12 use
    protocol 5 and don't sync with this one; they only see our version.
]]
local _, ns = ...
local S = ns.Sync

local PREFIX = "NootropicGM"
local PROTO = "6"
local LEGACY = "5"
S.PROTO = PROTO
S.MIN_VERSION = "2.12.0" -- the first version speaking protocol 6

local FS = "\t"
local Hash, Base36, Same, RosterEntry = S.Hash, S.Base36, S.Same, S.RosterEntry
local LANE_STORE, LANE_CHANNEL, LaneOf = S.LANE_STORE, S.LANE_CHANNEL, S.LaneOf
local function Now() return ns.DB:Now() end
local function Me() return ns.PlayerFullName() end
local P32 = 4294967291
local RawSend -- the transport, below

S.GROUPS = 32
S.CHUNK = 200            -- characters per piece of a long message
S.MAX_MSG = 250
S.MAX_PARTS = 16         -- pieces per message (3200 characters)
S.PACK_MAX = 2800        -- characters of payload per bundle or list message
S.BYTES_PER_SEC = 600    -- what we send, at most (gentler than ChatThrottleLib's 800)
S.BURST = 1800
S.ANSWER_WAIT = 3        -- seconds between candidate answerers
S.ANSWERERS = 4          -- how many candidates may answer one check
S.ASK_COOLDOWN = 60      -- per lane and author
S.FULL_COOLDOWN = 900    -- after asking for all of an author's records
S.MAX_ASKS = 20          -- requests answered per requester per minute
S.MAX_BACKLOG = 3000     -- answers wait while this many messages are queued
S.MAX_WHISPERS = 120     -- whispers read per guildmate per minute (relays)
S.RECHECK = 35           -- after catching up, check again once this much later
S.MAX_BUNDLE = 65536     -- characters of one unpacked bundle
S.ECHO_WAIT = 8          -- seconds for our first guild message to come back

------------------------------------------------------------------------
-- Fingerprints
------------------------------------------------------------------------
S.sumCache = {}

-- { [author] = { t = newest, h = sum, n = count } } for a lane
function S:AuthorSums(lane)
    local c = self.sumCache[lane]
    if c and c.version == self.storeVersion and GetTime() - c.at < 30 then return c.sums end
    local out = {}
    local store = self:Store(LANE_STORE[lane])
    if store then
        local now = Now()
        for key, rec in pairs(store) do
            if rec.a and LaneOf(key) == lane and not self:Excluded(key, rec, now) then
                local s = out[rec.a]
                if not s then s = { t = 0, h = 0, n = 0 }; out[rec.a] = s end
                if rec.t > s.t then s.t = rec.t end
                s.h = (s.h + Hash(key .. FS .. rec.t .. FS .. (rec.v or ""))) % P32
                s.n = s.n + 1
            end
        end
    end
    self.sumCache[lane] = { version = self.storeVersion, at = GetTime(), sums = out }
    return out
end

local function GroupOf(author) return Hash(author:lower()) % S.GROUPS + 1 end
local function AuthorPrint(author, s) return Hash(author .. ":" .. s.t .. ":" .. s.h) end

-- 32 group fingerprints and the root over them
function S:Groups(lane)
    local g = {}
    for i = 1, self.GROUPS do g[i] = 0 end
    for author, s in pairs(self:AuthorSums(lane)) do
        local i = GroupOf(author)
        g[i] = (g[i] + AuthorPrint(author, s)) % P32
    end
    local root = 0
    for i = 1, self.GROUPS do root = (root * 31 + g[i]) % P32 end
    return g, root
end

local function Entry(author, s) return author .. ":" .. Base36(s.t) .. ":" .. Base36(s.h) end

local function ParseEntries(text)
    local out, n = {}, 0
    for e in (text or ""):gmatch("[^,]+") do
        local a, t, h = e:match("^([^:]+):(%w+):(%w+)$")
        if a and #a <= 48 and not a:find("[|%c]") then
            out[S.CanonName(a)] = { t = tonumber(t, 36) or 0, h = tonumber(h, 36) or -1 }
            n = n + 1
            if n >= 2000 then break end
        end
    end
    return out
end

local function ParseNumbers(text, max)
    local out = {}
    for n in (text or ""):gmatch("%w+") do
        out[#out + 1] = tonumber(n, 36)
        if #out >= max then break end
    end
    return out
end

------------------------------------------------------------------------
-- Who's around: guildmates online whose copy speaks this protocol
------------------------------------------------------------------------
-- (No version known yet, as on a new install: assume so; a request they
-- don't answer is asked of someone else next time.)
function S:Speaks(name)
    local av = self:Get("AV:" .. name)
    return av == nil or ns.CompareVersions(av.v or "", self.MIN_VERSION) >= 0
end

function S:OnlinePeers()
    local out, me = {}, Me()
    for _, e in ipairs((ns.Roster and ns.Roster.members) or {}) do
        if e.online and not Same(e.full, me) and self:Speaks(e.full) then out[#out + 1] = e.full end
    end
    return out
end

-- Is anyone online running a copy from before 2.12?
function S:OlderCopyOnline()
    local me = Me()
    for _, e in ipairs((ns.Roster and ns.Roster.members) or {}) do
        if e.online and not Same(e.full, me) then
            local av = self:Get("AV:" .. e.full)
            if av and ns.CompareVersions(av.v or "", self.MIN_VERSION) < 0 then return true end
        end
    end
    return false
end

-- May `name` take part in this lane (as far as we can tell from here)?
function S:PeerInLane(name, lane)
    if lane == "officer" then return self:KnownOfficer(name) end
    if lane == "recruit" then return self:MayRecruitName(name) end
    return true
end

-- A well-spread number for a string. (The plain hash is linear: two names
-- differing in one letter always come out in the same order.) Integer math
-- below 2^53 only, so every copy gets the same result.
local function Spread(str)
    local h = Hash(str)
    for _ = 1, 3 do
        local lo, hi = h % 65536, math.floor(h / 65536)
        h = (lo * 40503 + hi * hi % 65521 * 2654 + lo * hi % 65537 + 1013904223) % P32
    end
    return h
end

-- Online guildmates in a lane (and us), ordered for `seed` the same way on
-- every copy; in the guild lane officers first (they hold everyone's records).
function S:Candidates(lane, seed, filter)
    local list = {}
    for _, name in ipairs(self:OnlinePeers()) do
        if self:PeerInLane(name, lane) and (not filter or filter(name)) then list[#list + 1] = name end
    end
    local me = Me()
    if self:InLane(lane) and (not filter or filter(me)) then list[#list + 1] = me end
    local function score(name)
        local officer = ((lane == "guild" or lane == "events") and self:KnownOfficer(name)) and 0 or 1
        return officer * P32 + Spread(seed:lower() .. "|" .. name:lower())
    end
    table.sort(list, function(a, b) return score(a) < score(b) end)
    return list
end

------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------
S.lane = {}        -- lane -> { state, with, at, behind }
S.answered = {}    -- "lane|asker" -> GetTime() someone answered their check
S.asked = {}       -- "lane|author" -> { at, full }
S.heardAsk = {}    -- "lane|author" -> { at, since }
S.answeredAsk = {} -- "lane|author|since" -> GetTime()
S.askCount = {}    -- requester -> { n, since }
S.rechecks = {}    -- lane -> re-checks this session

function S:LaneState(lane) return self.lane[lane] or { state = "idle" } end

local FINAL = { synced = true, catching = true, alone = true }
local function SetState(lane, state, with, behind)
    S.lane[lane] = { state = state, with = with, at = GetTime(), behind = behind }
    ns:Fire("SYNC_STATUS", lane)
    if S.reportLane == lane and FINAL[state] then
        S.reportLane = nil
        ns:Print(select(2, S:Health()) .. ".")
    end
end

-- Ask the lane how we compare (at login, and on /ngm sync).
function S:Check(lane)
    if not IsInGuild() or not ns.DB:Guild() or not self:InLane(lane) then return false end
    local _, root = self:Groups(lane)
    SetState(lane, "checking")
    self:Send(table.concat({ PROTO, "F", lane, Base36(root), "q", "" }, FS), LANE_CHANNEL[lane], nil, "high")
    C_Timer.After(self.ANSWER_WAIT * self.ANSWERERS + 5, function()
        if S:LaneState(lane).state == "checking" then SetState(lane, "alone") end
    end)
    return true
end

function S:CheckAll(force)
    local now = GetTime()
    if not force and now - (self.lastCheck or -1e9) < 10 then return false end
    self.lastCheck = now
    local any = false
    for _, lane in ipairs(self.LANES) do any = self:Check(lane) or any end
    return any
end

-- Someone asks: answer if it's our turn and nobody has yet.
-- (As someone's relay we always answer, at once: nobody else heard them.)
function S:OnCheck(lane, root, asker, relayFor)
    local k = lane .. "|" .. asker:lower()
    local pos = 1
    if not relayFor then
        local order = self:Candidates(lane, asker, function(n) return not Same(n, asker) end)
        local me = Me()
        pos = nil
        for i, n in ipairs(order) do if Same(n, me) then pos = i break end end
        if not pos or pos > self.ANSWERERS then return end
    end
    C_Timer.After(0.5 + (pos - 1) * self.ANSWER_WAIT, function()
        if GetTime() - (S.answered[k] or -1e9) < 30 then return end
        S.answered[k] = GetTime()
        local groups, mine = S:Groups(lane)
        local fields = { PROTO, "F", lane, Base36(mine), "a", asker }
        if mine ~= root then
            local g = {}
            for i = 1, S.GROUPS do g[i] = Base36(groups[i]) end
            fields[#fields + 1] = table.concat(g, ",")
        end
        S:Send(table.concat(fields, FS), LANE_CHANNEL[lane], nil, "high")
    end)
end

-- An answer to someone's check (maybe ours).
function S:OnCheckAnswer(lane, root, target, groupsText, who)
    self.answered[lane .. "|" .. target:lower()] = GetTime()
    if not Same(target, Me()) then return end
    local groups, mine = self:Groups(lane)
    if root == mine then
        SetState(lane, "synced", who)
        return
    end
    local theirs = ParseNumbers(groupsText, self.GROUPS)
    local differ = {}
    for i = 1, self.GROUPS do
        if (theirs[i] or -1) ~= groups[i] then differ[#differ + 1] = i end
    end
    SetState(lane, "comparing", who)
    self:SendEntries(lane, who, "1", differ)
end

-- Our per-author list for some groups.
function S:SendEntries(lane, target, step, groups)
    local want = {}
    for _, i in ipairs(groups) do want[i] = true end
    local entries = {}
    for author, s in pairs(self:AuthorSums(lane)) do
        if want[GroupOf(author)] then entries[#entries + 1] = Entry(author, s) end
    end
    table.sort(entries)
    local glist = {}
    for _, i in ipairs(groups) do glist[#glist + 1] = Base36(i) end
    local head = table.concat({ PROTO, "E", lane, target, step, table.concat(glist, ",") }, FS) .. FS
    local part, size = {}, 0
    local function flush()
        self:Send(head .. table.concat(part, ","), LANE_CHANNEL[lane], nil, "high")
        part, size = {}, 0
    end
    for _, e in ipairs(entries) do
        if size > 0 and size + #e + 1 > self.PACK_MAX then flush() end
        part[#part + 1] = e
        size = size + #e + 1
    end
    flush()
end

function S:OnEntries(lane, target, step, groupsText, entriesText, who)
    if not Same(target, Me()) then return end
    local groups = ParseNumbers(groupsText, self.GROUPS)
    if step == "1" then
        -- once per peer and check (a long list comes in several messages)
        local k = lane .. "|" .. who
        self.entriesSent = self.entriesSent or {}
        if GetTime() - (self.entriesSent[k] or -1e9) > 10 then
            self.entriesSent[k] = GetTime()
            self:SendEntries(lane, who, "2", groups)
        end
    end
    self:Pull(lane, who, ParseEntries(entriesText))
end

-- Who to ask for an author's records: the author when they're online,
-- otherwise one of the online guildmates whose copies we'd accept (officers;
-- anyone in the recruit and officer lanes), chosen per author so the work is
-- spread out. The peer we compared with, when nobody else fits.
function S:SourceFor(lane, author, peer, skip)
    local me = Me()
    local e = RosterEntry(author)
    if e and e.online and not Same(author, me) and not Same(author, skip) and self:Speaks(author) then return author end
    local list = self:Candidates(lane, author, function(n)
        return not Same(n, me) and not Same(n, skip) and self:MayRelay(n, lane)
    end)
    if list[1] then return list[1] end
    if not Same(peer, skip) and (Same(peer, author) or self:MayRelay(peer, lane)) then return peer end
end

-- Ask for whatever `theirs` shows we lack, from the best source for each author.
function S:Pull(lane, peer, theirs)
    local mine = self:AuthorSums(lane)
    local me = Me()
    local bySource, behind, waitFor = {}, 0, 0
    for author, t in pairs(theirs) do
        local m = mine[author]
        local since
        if not m then since = 0
        elseif m.h == t.h then since = nil
        elseif t.t > m.t then since = m.t
        elseif t.t == m.t then since = 0
        end
        -- (our own too: a new install gets back what we wrote before)
        if since then
            local k = lane .. "|" .. author
            local last = self.asked[k]
            -- asked before and still missing: try someone else this time
            local source = self:SourceFor(lane, author, peer, last and last.source)
                or self:SourceFor(lane, author, peer)
            if source then
                behind = behind + 1
                local cool = last and (last.full and self.FULL_COOLDOWN or self.ASK_COOLDOWN) or 0
                local left = last and (cool - (GetTime() - last.at)) or 0
                if left <= 0 then
                    self.asked[k] = { at = GetTime(), full = since == 0 and m ~= nil, source = source }
                    bySource[source] = bySource[source] or {}
                    table.insert(bySource[source], author .. ":" .. Base36(since))
                elseif left > waitFor then
                    waitFor = left
                end
            end
        end
    end
    if behind == 0 then
        SetState(lane, "synced", peer)
        return
    end
    SetState(lane, "catching", peer, behind)
    for source, pulls in pairs(bySource) do
        local head = table.concat({ PROTO, "Q", lane, source }, FS) .. FS
        local part, size = {}, 0
        for _, p in ipairs(pulls) do
            if size > 0 and size + #p + 1 > self.PACK_MAX then
                self:Send(head .. table.concat(part, ","), LANE_CHANNEL[lane], nil, "high")
                part, size = {}, 0
            end
            part[#part + 1] = p
            size = size + #p + 1
        end
        self:Send(head .. table.concat(part, ","), LANE_CHANNEL[lane], nil, "high")
    end
    -- check again once it's had time to arrive (once per lane at a time)
    self.rechecks[lane] = (self.rechecks[lane] or 0) + 1
    self.recheckDue = self.recheckDue or {}
    if self.rechecks[lane] <= 5 and not self.recheckDue[lane] then
        self.recheckDue[lane] = true
        local function recheck()
            -- still arriving: wait until it's quiet
            if GetTime() - (S.lastArrival or -1e9) < 10 then
                C_Timer.After(10, recheck)
                return
            end
            S.recheckDue[lane] = false
            S:Check(lane)
        end
        C_Timer.After(math.max(self.RECHECK, waitFor + 1), recheck)
    end
end

-- Someone asks for authors' records.
function S:OnAsk(lane, target, pullsText, who)
    local now = GetTime()
    local pulls = {}
    for p in (pullsText or ""):gmatch("[^,]+") do
        local author, since = p:match("^([^:]+):(%w+)$")
        if author then
            author = S.CanonName(author)
            since = tonumber(since, 36) or 0
            local k = lane .. "|" .. author
            local h = self.heardAsk[k]
            if not h or now - h.at > 20 or since < h.since then self.heardAsk[k] = { at = now, since = since } end
            pulls[#pulls + 1] = { author, since }
        end
        if #pulls >= 500 then break end
    end
    if not Same(target, Me()) then return end
    -- one requester can't keep us busy
    local r = self.askCount[who]
    if not r or now - r.since > 60 then
        r = { n = 0, since = now }
        self.askCount[who] = r
    end
    r.n = r.n + 1
    if r.n > self.MAX_ASKS or self:QueueSize() > self.MAX_BACKLOG then return end
    local me = Me()
    local want = {}
    for _, p in ipairs(pulls) do
        local author, since = p[1], p[2]
        local ak = lane .. "|" .. author .. "|" .. since
        if (Same(author, me) or self:MayRelay(me, lane)) and now - (self.answeredAsk[ak] or -1e9) > 20 then
            self.answeredAsk[ak] = now
            want[author:lower()] = math.min(want[author:lower()] or since, since)
        end
    end
    if not next(want) then return end
    local out, tnow = {}, Now()
    for key, rec in pairs(self:Store(LANE_STORE[lane]) or {}) do
        local since = rec.a and want[rec.a:lower()]
        if since and rec.t > since and LaneOf(key) == lane and not self:Excluded(key, rec, tnow) then
            out[#out + 1] = { key, rec }
        end
    end
    if #out > 0 then self:SendRecords(lane, out) end
end

------------------------------------------------------------------------
-- Sending records: one, or bundles
------------------------------------------------------------------------
local function Line(key, rec)
    return table.concat({ key, tostring(rec.t), rec.a or "", rec.b or "", rec.v or "" }, FS)
end

local function CanPack()
    local E = C_EncodingUtil
    return E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64 and true or false
end

local function Pack(text)
    local okC, packed = pcall(C_EncodingUtil.CompressString, text)
    if not okC or type(packed) ~= "string" then return nil end
    local okB, out = pcall(C_EncodingUtil.EncodeBase64, packed)
    if not okB or type(out) ~= "string" then return nil end
    return out
end

local function Unpack(text)
    if not CanPack() then return nil end
    local okB, packed = pcall(C_EncodingUtil.DecodeBase64, text)
    if not okB or type(packed) ~= "string" then return nil end
    local okD, v = pcall(C_EncodingUtil.DecompressString, packed)
    if not okD or type(v) ~= "string" or #v > S.MAX_BUNDLE then return nil end
    return v
end

-- Heavy records (recipe lists) go after everything else.
local HEAVY = { RP = true }
local function Order(a, b)
    local ha, hb = HEAVY[a[1]:match("^(%u+)")] and 1 or 0, HEAVY[b[1]:match("^(%u+)")] and 1 or 0
    if ha ~= hb then return ha < hb end
    return a[1] < b[1]
end

-- Sends records of one lane: compressed bundles where that's smaller,
-- single records otherwise. Your own go first. A record already waiting to
-- go out (same version) isn't queued again.
S.outgoing = {} -- key -> time of the version waiting to go out
function S:SendRecords(lane, list)
    local channel = LANE_CHANNEL[lane]
    local me = Me()
    local own, other = {}, {}
    for _, kr in ipairs(list) do
        if self.outgoing[kr[1]] ~= kr[2].t then
            table.insert(Same(kr[2].a, me) and own or other, kr)
        end
    end
    local function keysOf(items)
        local keys = {}
        for _, kr in ipairs(items) do
            keys[#keys + 1] = kr[1]
            self.outgoing[kr[1]] = kr[2].t
        end
        return keys
    end
    local function single(kr, prio)
        local msg = PROTO .. FS .. "R" .. FS .. Line(kr[1], kr[2])
        self:Send(msg, channel, nil, prio, msg, keysOf({ kr }))
    end
    local function bundle(items, prio)
        if #items == 1 or not CanPack() then
            for _, kr in ipairs(items) do single(kr, prio) end
            return
        end
        local lines = {}
        for _, kr in ipairs(items) do lines[#lines + 1] = Line(kr[1], kr[2]) end
        local plain = table.concat(lines, "\n")
        local packed = Pack(plain)
        if not packed or #packed >= #plain then
            for _, kr in ipairs(items) do single(kr, prio) end
        elseif #packed > self.PACK_MAX then
            local half = math.floor(#items / 2)
            bundle({ unpack(items, 1, half) }, prio)
            bundle({ unpack(items, half + 1) }, prio)
        else
            self:Send(table.concat({ PROTO, "B", lane, "z", packed }, FS), channel, nil, prio, packed, keysOf(items))
        end
    end
    if #own > 0 then
        table.sort(own, Order)
        bundle(own, "high")
    end
    if #other > 0 then
        table.sort(other, Order)
        for i = 1, #other, 200 do bundle({ unpack(other, i, math.min(i + 199, #other)) }, "bulk") end
    end
end

-- Live changes (the batching in Core/Records.lua calls this per record):
-- sent together at the end of the frame, per lane.
S.live = {}
function S:Broadcast(key, rec)
    local lane = LaneOf(key)
    if not lane or not self:InLane(lane) then return end
    self.live[lane] = self.live[lane] or {}
    table.insert(self.live[lane], { key, rec })
    if not self.liveTimer then
        self.liveTimer = true
        C_Timer.After(0, function()
            S.liveTimer = false
            local live = S.live
            S.live = {}
            for l, list in pairs(live) do S:SendRecords(l, list) end
        end)
    end
end

------------------------------------------------------------------------
-- Receiving records
------------------------------------------------------------------------
-- One record from the wire: tidied like our own edits, then applied.
function S:Intake(key, t, author, batch, value, ctx)
    t = tonumber(t)
    if not key or not t or key:find("[|%c]") or (author or ""):find("[|%c]") then return false end
    value = (value or ""):gsub("|", "/")
    if key:match("^(%u+):") ~= "A" then value = value:gsub(S.US, "") end
    value = value:gsub("[%z\1-\30\127]", " ")
    if batch and not batch:match("^%w%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?$") then batch = "" end
    local rec = { v = value, t = t, a = author, b = (batch ~= "" and batch) or nil }
    key, rec = S.Canon(key, rec)
    local applied = self:Apply(key, rec, ctx)
    if applied then self.lastArrival = GetTime() end
    self:Notify("member")
    return applied, key, rec
end

-- A record arrived (alone or in a bundle). relayFor: whispered to us, as
-- relay, by this guildmate: keep and pass on only their own records.
function S:Received(key, t, author, batch, value, who, channel, relayFor)
    if relayFor then
        if not Same(author, relayFor) or LaneOf(key) == "officer" then return end
        local _, k, rec = self:Intake(key, t, author, batch, value, { origin = "remote", channel = "GUILD", sender = who })
        local cur = k and self:Get(k)
        if cur and rec and cur.t == rec.t and Same(cur.a, rec.a) then self:Broadcast(k, cur) end
        return
    end
    self:Intake(key, t, author, batch, value, { origin = "remote", channel = channel, sender = who })
end

function S:OnBundle(lane, data, who, channel, relayFor)
    local text = Unpack(data or "")
    if not text then return end
    local n = 0
    for line in text:gmatch("[^\n]+") do
        n = n + 1
        if n > 1000 then break end
        local f = ns.Split(line, FS)
        if f[1] and LaneOf(f[1]) == lane then
            self:Received(f[1], f[2], f[3], f[4], table.concat(f, FS, 5), who, channel, relayFor)
        end
    end
end

------------------------------------------------------------------------
-- A guild channel that doesn't deliver
------------------------------------------------------------------------
function S:NoteGuildSent()
    if self.guildEcho or self.firstUnechoed then return end
    self.firstUnechoed = GetTime()
    C_Timer.After(self.ECHO_WAIT + 1, function() S:CheckEcho() end)
end

function S:GuildBroken()
    return not self.guildEcho and self.firstUnechoed ~= nil and GetTime() - self.firstUnechoed >= self.ECHO_WAIT
end

function S:CheckEcho()
    if self.relay or not self:GuildBroken() then return end
    self:NextRelay()
end

-- Whispers the next online officer we haven't tried: a tiny hello first (a
-- first whisper can be lost), then everything that matters again.
S.relayTried = {}
function S:NextRelay()
    local me = Me()
    local list = self:Candidates("guild", me, function(n)
        return not Same(n, me) and self:KnownOfficer(n) and not self.relayTried[n]
    end)
    local relay = list[1]
    self.relay, self.relayAcked = relay, false
    if not relay then return end
    self.relayTried[relay] = true
    RawSend(PROTO .. FS .. "H", "WHISPER", ns.ChatName(relay))
    C_Timer.After(2, function()
        if S.relay ~= relay then return end
        S:QueueOutgoing("AV:" .. me)
        S:FlushOutgoing()
        S:CheckAll(true)
    end)
    C_Timer.After(10, function()
        if S.relay == relay and not S.relayAcked then S:NextRelay() end
    end)
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
S.partials = {}
S.whispers = {}

function S:OnMessage(msg, channel, sender)
    local who = ns.NormalizeName(sender)
    if not who then return end
    if who == Me() then
        if channel == "GUILD" then self.guildEcho, self.relay = true, nil end
        return
    end
    local relayFor
    if channel == "WHISPER" then
        -- relays: officers read whispers from guildmates, not too many
        if not RosterEntry(who) then return end
        local kind = msg:match("^%w+\t(%u)")
        if kind == "K" then
            if Same(who, self.relay) then self.relayAcked = true end
            return
        end
        if not ns.IsOfficer() then return end
        local w = self.whispers[who]
        if not w or GetTime() - w.since > 60 then
            w = { n = 0, since = GetTime() }
            self.whispers[who] = w
        end
        w.n = w.n + 1
        if w.n > self.MAX_WHISPERS then return end
        if kind == "H" then
            RawSend(PROTO .. FS .. "K", "WHISPER", ns.ChatName(who))
            return
        end
        relayFor, channel = who, "GUILD"
    elseif channel ~= "GUILD" and channel ~= "OFFICER" then
        return -- party, raid, instance: not ours to read
    end
    if channel == "OFFICER" then
        local e = RosterEntry(who)
        if e then self.officers[who] = e.rankIndex end
        self:NoteOfficer(who)
    end
    local f = ns.Split(msg, FS)
    if f[1] == LEGACY then return self:OnLegacy(f, channel, who, relayFor) end
    if f[1] ~= PROTO then return end
    self.stats.received = self.stats.received + 1
    local kind = f[2]
    if kind == "C" then return self:OnPiece(f, channel, sender, relayFor) end
    if kind == "R" then
        if f[3] and LaneOf(f[3]) and LANE_CHANNEL[LaneOf(f[3])] == channel then
            self:Received(f[3], f[4], f[5], f[6], table.concat(f, FS, 7), who, channel, relayFor)
        end
        return
    end
    local lane = f[3]
    if not (lane and LANE_STORE[lane]) or LANE_CHANNEL[lane] ~= channel or not self:InLane(lane) then return end
    if kind == "B" then
        if f[4] == "z" then self:OnBundle(lane, f[5], who, channel, relayFor) end
    elseif kind == "F" then
        local root = tonumber(f[4] or "", 36)
        if not root then return end
        if f[5] == "q" then self:OnCheck(lane, root, who, relayFor)
        elseif f[5] == "a" and f[6] then self:OnCheckAnswer(lane, root, S.CanonName(f[6]), f[7], who) end
    elseif kind == "E" then
        self:OnEntries(lane, S.CanonName(f[4] or ""), f[5], f[6], f[7], who)
    elseif kind == "Q" then
        local target = S.CanonName(f[4] or "")
        if relayFor and not Same(target, Me()) then
            -- their request for someone else: ask on their behalf
            self:Send(table.concat({ PROTO, "Q", lane, target, f[5] or "" }, FS), "GUILD", nil, "high")
            return
        end
        self:OnAsk(lane, target, f[5], who)
    end
end

-- Copies before 2.12: we only read their version (so it shows, and so they
-- can be reminded to update).
function S:OnLegacy(f, channel, who, relayFor)
    if relayFor or channel ~= "GUILD" or f[2] ~= "R" or not Same(f[3], "AV:" .. who) then return end
    self:Intake(f[3], f[4], f[5], f[6], table.concat(f, FS, 7), { origin = "remote", channel = "GUILD", sender = who })
end

-- Pieces of a long message.
function S:OnPiece(f, channel, sender, relayFor)
    if self.reassembling then return end
    local id, i, n = f[3], tonumber(f[4]), tonumber(f[5])
    if not (id and i and n) or n < 1 or n > self.MAX_PARTS or i < 1 or i > n or i % 1 ~= 0 then return end
    local who = ns.NormalizeName(sender)
    local pkey = who .. ":" .. (relayFor and "W" or channel) .. ":" .. id
    local p = self.partials[pkey]
    if not p then
        local pending = 0
        for k in pairs(self.partials) do if k:sub(1, #who + 1) == who .. ":" then pending = pending + 1 end end
        if pending >= 8 then return end
        p = { parts = {}, count = 0, n = n, at = GetTime() }
        self.partials[pkey] = p
    end
    if n ~= p.n then return end
    if not p.parts[i] then
        p.parts[i] = table.concat(f, FS, 6)
        p.count = p.count + 1
    end
    for k, v in pairs(self.partials) do
        if GetTime() - v.at > 60 then self.partials[k] = nil end
    end
    if p.count < p.n then return end
    self.partials[pkey] = nil
    self.reassembling = true
    local ok, err = pcall(self.OnMessage, self, table.concat(p.parts), relayFor and "WHISPER" or channel, sender)
    self.reassembling = false
    if not ok then error(err, 0) end
end

------------------------------------------------------------------------
-- Transport: byte budget, priorities, retries, pieces
------------------------------------------------------------------------
local queues = { high = {}, bulk = {} }
local waiting = {} -- identical messages already queued (never queued twice)
local tokens, lastRefill
local chunkId = 0
S.queues, S.waiting = queues, waiting

local RESULT_RETRY = { [3] = 1, [8] = 1, [11] = 5 } -- throttle, channel throttle, combat lockdown (seconds)

RawSend = function(msg, channel, target)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if not send then return "drop" end
    local ok, res = pcall(send, PREFIX, msg, channel, target)
    if not ok then return "drop" end
    if res == nil or res == true or res == 0 then return "ok" end
    if type(res) == "number" and RESULT_RETRY[res] then return "retry", RESULT_RETRY[res] end
    return "drop"
end

-- keys: records in this message (no longer "waiting to go out" once sent)
function S:Send(msg, channel, target, prio, dedupe, keys)
    local q = queues[prio or "high"]
    if dedupe then
        if waiting[dedupe] then return end
        waiting[dedupe] = true
    end
    if #msg > self.MAX_MSG then
        local n = math.ceil(#msg / self.CHUNK)
        if n > self.MAX_PARTS then
            if dedupe then waiting[dedupe] = nil end
            for _, k in ipairs(keys or {}) do self.outgoing[k] = nil end
            self.stats.dropped = self.stats.dropped + 1
            return
        end
        chunkId = (chunkId + 1) % 46656
        local id = Base36(chunkId)
        for i = 1, n do
            local part = msg:sub((i - 1) * self.CHUNK + 1, i * self.CHUNK)
            q[#q + 1] = { table.concat({ PROTO, "C", id, tostring(i), tostring(n), part }, FS), channel, target,
                i == n and dedupe or nil, i == n and keys or nil }
        end
    else
        q[#q + 1] = { msg, channel, target, dedupe, keys }
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
            local channel, target = item[2], item[3]
            -- our guild messages go nowhere: whisper them to the relay
            -- instead; checks still also go on the guild channel, so we
            -- notice if it starts working again
            local probe = false
            if channel == "GUILD" and S.relay and S:GuildBroken() then
                probe = item[1]:find("^%w+\tF\t") ~= nil
                channel, target = "WHISPER", ns.ChatName(S.relay)
            end
            local result, wait = RawSend(item[1], channel, target)
            if result == "retry" then
                C_Timer.After(wait, step)
                return
            end
            if probe then RawSend(item[1], "GUILD") end
            table.remove(q, 1)
            if item[4] then waiting[item[4]] = nil end
            if item[5] then for _, k in ipairs(item[5]) do S.outgoing[k] = nil end end
            tokens = tokens - cost
            if result == "ok" then
                S.stats.sent = S.stats.sent + 1
                if channel == "GUILD" then S:NoteGuildSent() end
            else
                S.stats.dropped = S.stats.dropped + 1
            end
        end
        C_Timer.After(0.25, step)
    end
    step()
end

function S:QueueSize() return #queues.high + #queues.bulk end

------------------------------------------------------------------------
-- Status (/ngm sync, Options, the dot in the window's status bar)
------------------------------------------------------------------------
local LANE_LABEL = { guild = "Guild data", officer = "Officer data", recruit = "Recruiting data" }

local function Ago(at)
    local s = math.floor(GetTime() - (at or GetTime()))
    if s < 60 then return "just now" end
    if s < 3600 then return ("%d min ago"):format(s / 60) end
    return ("%d h ago"):format(s / 3600)
end

-- "ok", "busy", "alone" or "problem", and a short line to show.
function S:Health()
    if self:GuildBroken() then
        if self.relay then return "busy", "Your guild messages don't arrive; going through " .. self.relay end
        return "problem", "Your guild messages don't arrive, and no officer is online to go through"
    end
    local st = self:LaneState("guild")
    if st.state == "synced" then return "ok", "In sync with " .. (st.with or "your guild") end
    if st.state == "catching" then return "busy", ("Catching up (%d to fetch)"):format(st.behind or 0) end
    if st.state == "checking" or st.state == "comparing" then return "busy", "Checking with your guild..." end
    if st.state == "alone" then return "alone", "No one online to compare with" end
    return "alone", "Not checked yet"
end

function S:StatusLines()
    local out = {}
    for _, lane in ipairs(self.LANES) do
        if self:InLane(lane) then
            local st = self:LaneState(lane)
            local text = ({
                synced = "in sync with " .. tostring(st.with),
                catching = ("catching up from %s (%d to fetch)"):format(tostring(st.with), st.behind or 0),
                checking = "checking...", comparing = "comparing with " .. tostring(st.with) .. "...",
                alone = "no one online to compare with",
            })[st.state] or "not checked yet"
            out[#out + 1] = ("%s: %s%s"):format(LANE_LABEL[lane], text, st.at and (" (" .. Ago(st.at) .. ")") or "")
        end
    end
    if self:GuildBroken() then
        out[#out + 1] = self.relay
            and ("|cffff2020Your guild messages don't arrive|r (a game issue); sending through %s%s."):format(self.relay, self.relayAcked and "" or ", waiting for them to answer")
            or "|cffff2020Your guild messages don't arrive|r (a game issue), and no officer running the addon is online to send them through."
    end
    local ranks = {}
    for _, r in ipairs(ns.DB:GuildRanks()) do
        local e = { rankIndex = r.index, rank = r.name }
        if r.index == 0 or self:RankIsOfficer(e) then ranks[#ranks + 1] = r.name end
    end
    out[#out + 1] = "Officer ranks (from the game's rank settings): " .. (#ranks > 0 and table.concat(ranks, ", ") or "not known yet")
    local st = self.stats
    out[#out + 1] = ("This session: %d sent, %d received, %d changes applied%s."):format(st.sent, st.received, st.applied,
        st.refused > 0 and (", " .. st.refused .. " refused") or "")
    local lr = self.lastRefused
    if lr then
        out[#out + 1] = ("Last refused: %s from %s (written as %s): %s."):format(tostring(lr.key), tostring(lr.sender), tostring(lr.author), lr.why)
    end
    return out
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function S:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
        if prefix ~= PREFIX then return end
        if issecretvalue and (issecretvalue(sender) or issecretvalue(msg)) then return end
        local ok, err = pcall(S.OnMessage, S, msg, channel, sender)
        if not ok then S.lastError = tostring(err) end
    end)

    -- Once the roster has told us your full name (before that the game may
    -- give only your first name): your version (sent only when it changed;
    -- the check finds anyone who missed it), then compare with whoever's
    -- online. Copies before 2.12 online get your version in their format,
    -- so they're told to update.
    local announced = false
    local function announceVersion()
        if announced or not S.readyFor or not (ns.Roster and ns.Roster.selfRow) then return end
        announced = true
        local me = Me()
        S:Set("AV:" .. me, ns.version, { force = true })
        local rec = S:Get("AV:" .. me)
        if rec and S:OlderCopyOnline() then
            S:Send(table.concat({ LEGACY, "R", "AV:" .. me, tostring(rec.t), me, "", rec.v }, FS), "GUILD", nil, "bulk")
        end
        C_Timer.After(3 + math.random() * 4, function() S:CheckAll(true) end)
    end
    S.AnnounceVersion = announceVersion

    -- Guild data arrives a little after login; prepare once it's there.
    local function ready()
        local key = ns.DB:GuildKey()
        if not key or S.readyFor == key or not ns.DB:Guild() then return end
        S.readyFor = key
        S:CanonicalizeSaved()
        S:PurgeUnknown()
        S:PruneAudit()
        S:PruneExpired()
        S:RebuildAll()
        S:PublishRanks()
        announceVersion()
    end
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", ready)
    -- rank settings changed (Guild Control): read them again
    ns:RegisterEvent("GUILD_RANKS_UPDATE", function()
        S.flagCache = {}
        S:PublishRanks()
    end)
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", ready)
    ready()

    -- the roster spells your name differently than expected: announce again
    ns:On("SELF_NAME_CHANGED", function()
        if not S.readyFor then return end
        announced = false
        announceVersion()
        if ns.Comm then ns.Comm:Report() end
    end)
    ns:On("ROSTER_UPDATED", announceVersion)

    -- send queued changes when logging out or reloading (best effort; the
    -- next check catches anything missed)
    ns:RegisterEvent("PLAYER_LOGOUT", function() S:FlushOutgoing() end)
end
