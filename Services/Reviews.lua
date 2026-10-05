--[[
    Nootropic Guild Manager - Anonymous guild reviews
    Any guildmate can rate the guild 1-5 stars and write a message, once every
    7 days. Only officers can read reviews; officers can comment on them (other
    officers see the comments) but nobody can change or delete a review.
    Reviews and comments are kept for a year.

    Keeping reviews anonymous
      - A review never carries a name: its id is random, its record has no
        author, and it's dated by day only (no time of day).
      - It isn't sent the moment you click Submit, but 2-15 minutes later, so
        the time it shows up can't be matched to who was online.
      - It goes to ONE officer running the addon (whispered addon message), not
        to the whole guild. That officer's copy saves it without a name and
        shares it with the other officers on the officer channel.
      - Limits of what an addon can do: the game itself tells the receiving
        officer's client who sent any addon message. This addon throws that
        name away and never saves or shows it, but someone running their own
        tools to watch addon traffic could see it.
      - "Once every 7 days" is remembered by your own copy of the addon (per
        account and guild), since the guild can't know who wrote what.

    Sync records (officer scope, see Core/Sync.lua)
      GR:<id>            "stars;text"  time = the day it was written, author = ""
      GC:<review>:<id>   "text"        author = the officer ("" = deleted by them)
]]
local _, ns = ...
local RV = {}
ns.Reviews = RV

RV.COOLDOWN = 7 * 86400       -- one review per 7 days
RV.KEEP = 365 * 86400         -- reviews and comments are kept a year
RV.TEXT_MAX = 500
RV.COMMENT_MAX = 200
RV.SEND_MIN, RV.SEND_MAX = 120, 900 -- send this many seconds after Submit
RV.RETRY = 600                -- try again if no officer confirmed it
RV.BEACON_FRESH = 1500        -- officers seen within this many seconds count as online
RV.OUTBOX_DAYS = 30           -- give up on a review nobody could receive

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Now() return ns.DB:Now() end
local function Day(t) return math.floor(t / 86400) * 86400 end
local function Changed() ns:Fire("REVIEWS_CHANGED") end

local function RandomId(n)
    local out = {}
    for i = 1, n do
        local d = math.random(0, 35)
        out[i] = B36:sub(d + 1, d + 1)
    end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Writing a review
------------------------------------------------------------------------
local function ReviewedTable()
    local s = ns.DB:Settings()
    s.reviewed = s.reviewed or {}
    return s.reviewed
end

-- Seconds until this account may review the current guild again.
function RV:Wait()
    local key = ns.DB:GuildKey()
    local last = key and ReviewedTable()[key]
    if not last then return 0 end
    return math.max(0, last + self.COOLDOWN - Now())
end

function RV:Outbox()
    local g = ns.DB:Guild()
    if not g then return {} end
    g.reviewOutbox = g.reviewOutbox or {}
    return g.reviewOutbox
end

function RV:PendingCount()
    local n = 0
    for _ in pairs(self:Outbox()) do n = n + 1 end
    return n
end

function RV.FormatWait(sec)
    if sec >= 86400 then
        local d = math.ceil(sec / 86400)
        return d == 1 and "1 day" or (d .. " days")
    end
    local h = math.ceil(sec / 3600)
    return h == 1 and "1 hour" or (h .. " hours")
end

function RV:Submit(stars, text)
    if not IsInGuild() or not ns.DB:Guild() then return false, "Join a guild first." end
    if not ns.DB:ReviewsEnabled() then return false, "Officers have turned guild reviews off." end
    stars = tonumber(stars)
    if not stars or stars < 1 or stars > 5 or stars ~= math.floor(stars) then
        return false, "Choose 1 to 5 stars."
    end
    text = ns.Trim(ns.Sync.Clean(text or "")):sub(1, self.TEXT_MAX)
    if text == "" then return false, "Write a few words about the guild." end
    local wait = self:Wait()
    if wait > 0 then return false, "You can write another review in " .. self.FormatWait(wait) .. "." end
    local now = Now()
    self:Outbox()[RandomId(12)] = {
        stars = stars, text = text, day = Day(now), created = now,
        sendAt = now + math.random(self.SEND_MIN, self.SEND_MAX),
    }
    ReviewedTable()[ns.DB:GuildKey()] = now
    Changed()
    return true
end

-- An officer running the addon who's online now (never yourself), or nil.
function RV:PickOfficer()
    local me, now, list = ns.PlayerFullName(), GetTime(), {}
    for full, at in pairs(ns.Sync.officerBeacons) do
        local e = ns.Roster.byName[full]
        if full ~= me and now - at < self.BEACON_FRESH and e and e.online then list[#list + 1] = full end
    end
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.random(1, #list)]
end

-- Sends reviews whose time has come. Runs every 30 seconds.
function RV:Pump()
    local g = ns.DB:Guild()
    if not (g and g.reviewOutbox and IsInGuild()) then return end
    local now = Now()
    local S = ns.Sync
    for id, item in pairs(g.reviewOutbox) do
        if now - item.created > self.OUTBOX_DAYS * 86400 then
            g.reviewOutbox[id] = nil
            Changed()
        elseif now >= item.sendAt and (not item.tried or now - item.tried >= self.RETRY) then
            local officer = self:PickOfficer()
            if officer then
                item.tried = now
                S:Send(table.concat({ S.PROTO, "V", id, tostring(item.stars), tostring(item.day), item.text }, S.FS),
                    "WHISPER", ns.ChatName(officer), "bulk")
            elseif ns.IsOfficer() then
                -- no other officer around: an officer's own review is saved directly
                self:Store(id, item.stars, item.text, item.day)
                g.reviewOutbox[id] = nil
                Changed()
            end
        end
    end
end

-- Saves a review as an anonymous officer record (no author, dated by day).
function RV:Store(id, stars, text, day)
    return ns.Sync:Set("GR:" .. id, ("%d;%s"):format(stars, text), { author = "", time = day, noBatch = true })
end

function RV:OnMessage(kind, f, sender)
    if kind == "V" then
        if not ns.IsOfficer() then return end
        local id, stars, day = f[3], tonumber(f[4]), tonumber(f[5])
        local text = ns.Trim(table.concat(f, ns.Sync.FS, 6))
        local now = Now()
        if not (id and id:match("^%w+$") and #id <= 16) then return end
        if not stars or stars < 1 or stars > 5 then return end
        if not day or Day(day) ~= day or day > now + 86400 or day < now - (self.OUTBOX_DAYS + 1) * 86400 then return end
        if text == "" or #text > self.TEXT_MAX then return end
        -- `sender` is only used to say "got it"; it's never stored
        self:Store(id, math.floor(stars), text, day)
        local S = ns.Sync
        S:Send(table.concat({ S.PROTO, "K", id }, S.FS), "WHISPER", ns.ChatName(sender), "bulk")
    elseif kind == "K" then
        local out = self:Outbox()
        if f[3] and out[f[3]] then
            out[f[3]] = nil
            Changed()
        end
    end
end

------------------------------------------------------------------------
-- Reading (officers)
------------------------------------------------------------------------
-- { { id, stars, text, day, comments = { {id, text, at, by}, ... } }, ... } newest first
function RV:List()
    local out, byId = {}, {}
    local store = ns.IsOfficer() and ns.Sync:Store("officer")
    if not store then return out end
    local cutoff = Now() - self.KEEP
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "GR:" and rec.t >= cutoff then
            local stars, text = rec.v:match("^(%d);(.*)$")
            if stars then
                local r = { id = key:sub(4), stars = tonumber(stars), text = text, day = rec.t, comments = {} }
                out[#out + 1] = r
                byId[r.id] = r
            end
        end
    end
    for key, rec in pairs(store) do
        if key:sub(1, 3) == "GC:" and rec.v ~= "" and rec.t >= cutoff then
            local rid, cid = key:match("^GC:([^:]+):(.+)$")
            local r = rid and byId[rid]
            if r then r.comments[#r.comments + 1] = { id = cid, text = rec.v, at = rec.t, by = rec.a } end
        end
    end
    for _, r in ipairs(out) do
        table.sort(r.comments, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            return a.id < b.id
        end)
    end
    table.sort(out, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        return a.id > b.id
    end)
    return out
end

function RV:Get(id)
    for _, r in ipairs(self:List()) do if r.id == id then return r end end
end

-- average, count, { [stars] = count }
function RV:Stats(list)
    list = list or self:List()
    local sum, by = 0, { 0, 0, 0, 0, 0 }
    for _, r in ipairs(list) do
        sum = sum + r.stars
        by[r.stars] = by[r.stars] + 1
    end
    return #list > 0 and sum / #list or 0, #list, by
end

function RV:AddComment(reviewId, text)
    if not ns.IsOfficer() then return false, "Only officers can comment on reviews." end
    text = ns.Trim(ns.Sync.Clean(text or "")):sub(1, self.COMMENT_MAX)
    if text == "" then return false, "Write a comment first." end
    local cid = ns.Sync.Base36(Now()) .. RandomId(3)
    return ns.Sync:Set("GC:" .. reviewId .. ":" .. cid, text)
end

-- Officers can delete their own comments (never reviews).
function RV:DeleteComment(reviewId, commentId)
    local key = "GC:" .. reviewId .. ":" .. commentId
    local rec = ns.Sync:Get(key)
    if not rec or rec.a ~= ns.PlayerFullName() then return false, "You can only delete your own comments." end
    return ns.Sync:Set(key, "")
end

function RV:Init()
    local function tick()
        RV:Pump()
        C_Timer.After(30, tick)
    end
    C_Timer.After(30, tick)
end
