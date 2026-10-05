--[[
    Nootropic Guild Manager - Guild polls
    Officers create polls (a question and 2-6 answers) and choose when voting
    closes (minutes, hours or days; 1 week by default). Everyone in the guild
    running the addon can vote once and change their vote until it closes.
    Closed polls keep showing their results for a number of days chosen when
    the poll is made (7 by default), then they're deleted.

    Sync records (guild scope, see Core/Sync.lua)
      PL:<id>             "closeAt;expireAt;deleted;question;answer1;answer2;..."   officers
      PV:<id>:<member>    answer number   the voter only, counted if cast before closeAt
      PI:<id>             "color;icon"    officers (the poll's look, like a tag's)
]]
local _, ns = ...
local P = {}
ns.Polls = P

P.MIN_OPTIONS, P.MAX_OPTIONS = 2, 6
P.QUESTION_MAX = 120
P.OPTION_MAX = 40
P.DEFAULT_CLOSE = { 7, "days" } -- 1 week
P.DEFAULT_KEEP_DAYS = 7
P.MAX_CLOSE = 365 * 86400
P.MAX_KEEP_DAYS = 365
P.UNITS = {
    { key = "minutes", label = "Minutes", secs = 60 },
    { key = "hours",   label = "Hours",   secs = 3600 },
    { key = "days",    label = "Days",    secs = 86400 },
}

local function Now() return ns.DB:Now() end

function P.UnitSeconds(key)
    for _, u in ipairs(P.UNITS) do if u.key == key then return u.secs end end
end

function P.UnitLabel(key)
    for _, u in ipairs(P.UNITS) do if u.key == key then return u.label end end
end

-- "2d 5h", "3h 10m", "12m"
function P.FormatSpan(secs)
    secs = math.max(0, math.floor(secs))
    local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
    if d > 0 then return h > 0 and ("%dd %dh"):format(d, h) or ("%dd"):format(d) end
    if h > 0 then return m > 0 and ("%dh %dm"):format(h, m) or ("%dh"):format(h) end
    return ("%dm"):format(math.max(1, m))
end

------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------
local function Codec() return ns.Sync.Codec end

-- Every poll still kept, with its votes counted:
-- { id, question, options, closeAt, expireAt, created, author, open, counts = {...},
--   total, myVote, voters = { [member] = answer } }
-- Open polls first (closing soonest first), then closed ones (newest first).
function P:List()
    local out = {}
    local store = ns.DB:Guild() and ns.Sync:Store("guild")
    if not store then return out end
    local now, byId = Now(), {}
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "PL:" then
            local p = Codec().ParsePoll(rec.v)
            if p and not p.deleted and p.expireAt >= now and #p.options >= self.MIN_OPTIONS then
                p.id = key:sub(4)
                p.author = rec.a
                p.created = tonumber(p.id:match("^(%w+)%-"), 36) or rec.t
                p.open = now < p.closeAt
                p.counts, p.total, p.voters = {}, 0, {}
                for i = 1, #p.options do p.counts[i] = 0 end
                out[#out + 1] = p
                byId[p.id] = p
            end
        end
    end
    local me = ns.PlayerFullName()
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "PI:" then
            local p = byId[key:sub(4)]
            if p then p.color, p.icon = Codec().ParsePollLook(rec.v) end
        end
    end
    -- polls without a look (made before polls had one)
    for _, p in ipairs(out) do
        if not p.color then
            local n = 0
            for i = 1, #p.id do n = n + p.id:byte(i) end -- the same color every time
            p.color = ns.Data:NextColor(n)
        end
        p.icon = p.icon or "Interface\\Icons\\INV_Scroll_03"
    end
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "PV:" then
            local id, voter = key:match("^PV:([^:]+):(.+)$")
            local p = id and byId[id]
            local choice = tonumber(rec.v)
            if p and choice and p.counts[choice] and rec.t <= p.closeAt + 60 then
                p.counts[choice] = p.counts[choice] + 1
                p.total = p.total + 1
                p.voters[voter] = choice
                if voter == me then p.myVote = choice end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.open ~= b.open then return a.open end
        if a.open then
            if a.closeAt ~= b.closeAt then return a.closeAt < b.closeAt end
        elseif a.closeAt ~= b.closeAt then
            return a.closeAt > b.closeAt
        end
        return a.id > b.id
    end)
    return out
end

function P:Get(id)
    for _, p in ipairs(self:List()) do if p.id == id then return p end end
end

function P:OpenCount()
    local n = 0
    for _, p in ipairs(self:List()) do if p.open then n = n + 1 end end
    return n
end

------------------------------------------------------------------------
-- Officers: create, close, delete
------------------------------------------------------------------------
function P:CanCreate() return ns.IsOfficer() end

local function CleanText(s, max)
    return ns.Trim(ns.Sync.Clean(s or ""):gsub(";", ",")):sub(1, max)
end

-- closeIn: seconds until voting closes.  keepDays: days results stay after that.
-- color, icon: the poll's look (like a tag's).
function P:Create(question, options, closeIn, keepDays, color, icon)
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    if not self:CanCreate() then return nil, "Only officers can create polls." end
    question = CleanText(question, self.QUESTION_MAX)
    if question == "" then return nil, "Write a question." end
    local answers, seen = {}, {}
    for _, o in ipairs(options or {}) do
        o = CleanText(o, self.OPTION_MAX)
        if o ~= "" then
            if seen[o:lower()] then return nil, ("\"%s\" is listed twice."):format(o) end
            seen[o:lower()] = true
            answers[#answers + 1] = o
        end
    end
    if #answers < self.MIN_OPTIONS then return nil, "Add at least two answers." end
    if #answers > self.MAX_OPTIONS then return nil, ("Polls can have up to %d answers."):format(self.MAX_OPTIONS) end
    closeIn = math.floor(tonumber(closeIn) or 0)
    if closeIn < 60 then return nil, "Voting has to stay open for at least 1 minute." end
    if closeIn > self.MAX_CLOSE then return nil, "Voting can stay open for at most 365 days." end
    keepDays = math.floor(tonumber(keepDays) or -1)
    if keepDays < 0 or keepDays > self.MAX_KEEP_DAYS then
        return nil, ("Keep results for 0 to %d days."):format(self.MAX_KEEP_DAYS)
    end
    local now = Now()
    local id = ns.Sync.Base36(now) .. "-" .. ns.Sync.Base36(math.random(0, 46655))
    local closeAt = now + closeIn
    local ok, err = ns.Sync:Set("PL:" .. id, Codec().Poll({
        closeAt = closeAt, expireAt = closeAt + keepDays * 86400, question = question, options = answers,
    }))
    if not ok then return nil, err end
    if color or icon then self:SetLook(id, color, icon) end
    self:MarkSeen(id)
    return id
end

-- Officers: a poll's color and icon.
function P:SetLook(id, color, icon)
    if not ns.IsOfficer() then return nil, "Only officers can change polls." end
    local p = self:Get(id)
    if not p then return nil, "Poll not found." end
    return ns.Sync:Set("PI:" .. id, Codec().PollLook(color or p.color, tostring(icon or p.icon or "")))
end

local function Rewrite(id, change)
    if not ns.IsOfficer() then return nil, "Only officers can change polls." end
    local rec = ns.Sync:Get("PL:" .. id)
    local p = rec and Codec().ParsePoll(rec.v)
    if not p then return nil, "Poll not found." end
    change(p)
    return ns.Sync:Set("PL:" .. id, Codec().Poll(p))
end

-- Ends voting now; the results stay for as long as they would have after closing.
function P:CloseNow(id)
    return Rewrite(id, function(p)
        local now = Now()
        if now >= p.closeAt then return end
        local keep = p.expireAt - p.closeAt
        p.closeAt = now
        p.expireAt = now + keep
    end)
end

function P:Delete(id)
    return Rewrite(id, function(p) p.deleted = true end)
end

------------------------------------------------------------------------
-- Voting
------------------------------------------------------------------------
function P:Vote(id, choice)
    local me = ns.PlayerFullName()
    if not (me and ns.DB:Guild()) then return nil, "You are not in a guild." end
    local p = self:Get(id)
    if not p then return nil, "Poll not found." end
    if not p.open then return nil, "Voting on this poll has closed." end
    if not p.options[choice] then return nil, "Pick an answer." end
    if p.myVote == choice then return true end
    return ns.Sync:Set("PV:" .. id .. ":" .. me, tostring(choice))
end

------------------------------------------------------------------------
-- Telling people about new polls (once each)
------------------------------------------------------------------------
local function SeenTable()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.pollsSeen = g.pollsSeen or {}
    return g.pollsSeen
end

function P:MarkSeen(id)
    local seen = SeenTable()
    if seen then seen[id] = Now() end
end

function P:Announce()
    local seen = SeenTable()
    if not seen then return end
    local me = ns.PlayerFullName()
    local kept = {}
    for _, p in ipairs(self:List()) do
        kept[p.id] = true
        if not seen[p.id] then
            seen[p.id] = Now()
            if p.open and not p.myVote and p.author ~= me then
                ns:Print(("New guild poll: |cffffffff%s|r  Vote on the %s tab (|cffffffff/ngm polls|r). Closes in %s.")
                    :format(p.question, ns.TabName("polls"), P.FormatSpan(p.closeAt - Now())))
            end
        end
    end
    -- forget polls that are gone
    for id in pairs(seen) do if not kept[id] then seen[id] = nil end end
end

function P:Init()
    ns:On("POLLS_CHANGED", function() ns.Debounce("pollannounce", 3, function() P:Announce() end) end)
    -- closing times pass without any message arriving
    local function tick()
        if IsInGuild() then ns:Fire("POLLS_TICK") end
        C_Timer.After(30, tick)
    end
    C_Timer.After(30, tick)
end
