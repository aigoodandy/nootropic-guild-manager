--[[
    Nootropic Guild Manager - Hall of Fame
    Guild leaderboards from the game's own character statistics (the
    Statistics page of the achievement window). The game only lets addons
    read your own, so each member's copy reads theirs and shares them as

      HF:<member> = "1;<month>;<all time>;<this month>;<last month id>;<last month>"

    <month> is the UTC month the record was written in (202611); each list
    is "key=n,key=n" (keys in HF.STATS). "This month" and "last month" are
    worked out by the member's own copy from a snapshot taken the first time
    it reads the statistics in a new month, so the first month counts from
    when the addon was installed. Gold is left out on purpose.

    Also: Social Butterfly (guild chat time, counted by your own copy),
    last month's champions (HF:Champions; titles written down by officers as
    HW:<month>), plausibility limits on everyone's numbers (HF.Plausible),
    and officers leaving someone out (HX:<member>). A person's main and alts
    always count as one. Champion titles (HF:TitleText) and announcing them
    in guild chat (HF:Announce, HA:<month>). Checks against the game's
    statistics comparison live in Services/HofCheck.lua.

    Statistic IDs were read from the Forever client's own catalogue
    (build 1.60.1, Interface 16001), the Wrath-era set plus Forever additions.
    GetStatistic returns text: "1,234", "--" for never, or a money string.
]]
local _, ns = ...
local HF = {}
ns.HallOfFame = HF

HF.VERSION = "1"
HF.PUBLISH_EVERY = 600 -- shared again at most every 10 minutes (and at login)

-- key, statistic id(s), label, icon. A list of ids is added up.
HF.STATS = {
    { key = "champs",   label = "Most Champion Wins", icon = "Interface\\Icons\\INV_Crown_01", computed = true, noChampion = true,
      tip = "Champion titles: each card's leader for a month (all of them, on a tie) wins its title. Recorded by officers' copies of the addon a few days into the next month, so nobody can award themselves one." },
    { key = "social",   label = "Social Butterfly", icon = "Interface\\Icons\\Spell_Holy_MindVision", rate = 8, since = 1793491200,
      format = function(n) return ("%.1f h"):format(n / 4) end,
      tip = "Hours spent in guild chat conversations: 15-minute blocks where you and at least one guildmate both spoke (8 blocks a day at most). Only the count is shared, never what was said." },
    { key = "quests",   id = 98,   rate = 150, label = "Quests completed",  icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "kills",    id = 1197, rate = 4000, label = "Kills",             icon = "Interface\\Icons\\Ability_DualWield" },
    { key = "bosses",   rate = 60, label = "Dungeon & raid bosses",         icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      tip = "Final bosses killed: every dungeon and raid, Forever's own included." },
    { key = "dungeons", id = 932,  rate = 60, label = "Dungeons entered",  icon = "Interface\\Icons\\INV_Misc_Key_14" },
    { key = "hk",       id = 588,  rate = 3000, label = "Honorable kills",   icon = "Interface\\Icons\\INV_BannerPVP_02" },
    { key = "bgs",      id = 840,  rate = 40, label = "Battlegrounds won", icon = "Interface\\Icons\\INV_Sword_27" },
    { key = "duels",    id = 319,  rate = 300, label = "Duels won",         icon = "Interface\\Icons\\Ability_Parry" },
    { key = "epics",    id = 341,  rate = 40, label = "Epics looted",      icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" },
    { key = "deaths",   id = 60,   rate = 300, label = "Deaths",            icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
    { key = "falls",    id = 114,  rate = 200, label = "Deaths from falling", icon = "Interface\\Icons\\Spell_Magic_FeatherFall" },
    { key = "flights",  id = 349,  rate = 150, label = "Flights taken",     icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
    { key = "hearths",  id = 353,  rate = 100, label = "Hearthstones used", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
    { key = "fish",     id = 1518, rate = 1500, label = "Fish caught",       icon = "Interface\\Icons\\INV_Misc_Fish_02" },
    { key = "hugs",     id = 1042, rate = 3000, label = "Hugs given",        icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
}
HF.BY_KEY = {}
for _, s in ipairs(HF.STATS) do HF.BY_KEY[s.key] = s end

-- Formats a statistic's value for display.
function HF.Format(stat, n)
    if stat and stat.format then return stat.format(n or 0) end
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- Final-boss kill statistics, one per dungeon or raid.
HF.BOSS_IDS = {
    15027, 15028, 63570, 1092, 15029, 6137, 63573, 63571, 63572, 63589, 6140, 6139, 1093, 6786,
    6141, 6142, 1094, 6143, 6144, 1095, 6145, 1096, 6146, 15030, 15031, 1098, 63574, 63575, 63581, 63580,
}

local function Me() return ns.PlayerFullName() end

-- UTC month as a number: 202611
function HF.Month(t)
    return tonumber(date("!%Y%m", t or time()))
end

function HF.PrevMonth(m)
    local y, mo = math.floor(m / 100), m % 100
    if mo == 1 then return (y - 1) * 100 + 12 end
    return y * 100 + mo - 1
end

------------------------------------------------------------------------
-- Reading your own statistics
------------------------------------------------------------------------
function HF:Available()
    return type(GetStatistic) == "function"
end

-- "1,234" -> 1234; "--", money strings and anything unreadable -> nil
function HF.Parse(raw)
    if type(raw) == "number" then return raw end
    if type(raw) ~= "string" or raw == "" or raw == "--" then return nil end
    if raw:find("|", 1, true) then return nil end -- money (coin textures)
    local digits = raw:match("^%s*([%d,%.%s]+)")
    if not digits then return nil end
    return tonumber((digits:gsub("[^%d]", "")))
end

local function Read(id)
    local ok, raw = pcall(GetStatistic, id)
    if not ok then return nil end
    if issecretvalue and issecretvalue(raw) then return nil end
    return HF.Parse(raw)
end

-- { key = n } for every statistic the game answered (nil when it can't).
function HF:ReadMine()
    local out, any = {}, false
    local social = self:SocialTotal()
    if social > 0 then out.social, any = social, true end
    if not self:Available() then return any and out or nil end
    for _, s in ipairs(self.STATS) do
        local n
        if s.id then
            n = Read(s.id)
        elseif s.key == "bosses" then
            for _, id in ipairs(self.BOSS_IDS) do
                local v = Read(id)
                if v then n = (n or 0) + v end
            end
        end
        if n then
            out[s.key] = n
            any = true
        end
    end
    return any and out or nil
end

------------------------------------------------------------------------
-- Monthly snapshots (this computer, per character)
------------------------------------------------------------------------
local function Minus(a, b)
    local out = {}
    for k, v in pairs(a) do
        local d = v - ((b and b[k]) or 0)
        if d > 0 then out[k] = d end
    end
    return out
end

-- Updates the snapshots in `state` for statistics `cur` read in `month`;
-- returns this month's and last month's numbers.
function HF.Advance(state, cur, month)
    if not state.month then
        state.month, state.base = month, cur
    elseif state.month ~= month then
        if state.month == HF.PrevMonth(month) then
            state.last, state.lastMonth = Minus(cur, state.base), state.month
        else
            state.last, state.lastMonth = nil, nil -- not played last month
        end
        state.month, state.base = month, cur
    end
    -- a statistic that went down (reset by the game): start it over
    for k, v in pairs(cur) do
        if state.base[k] and v < state.base[k] then state.base[k] = v end
    end
    return Minus(cur, state.base), state.last or {}
end

local function MyState()
    local s = ns.DB:Settings()
    s.hof = s.hof or {}
    local me = Me()
    s.hof[me] = s.hof[me] or {}
    return s.hof[me]
end

------------------------------------------------------------------------
-- The shared record
------------------------------------------------------------------------
local function EncodeList(t)
    local parts = {}
    for _, s in ipairs(HF.STATS) do
        if t[s.key] then parts[#parts + 1] = s.key .. "=" .. math.floor(t[s.key]) end
    end
    return table.concat(parts, ",")
end

local function DecodeList(v)
    local t = {}
    for k, n in (v or ""):gmatch("(%w+)=(%d+)") do
        if HF.BY_KEY[k] and not HF.BY_KEY[k].computed then t[k] = tonumber(n) end
    end
    return t
end

function HF.Encode(month, all, this, lastMonth, last)
    return table.concat({ HF.VERSION, tostring(month), EncodeList(all), EncodeList(this),
                          tostring(lastMonth or 0), EncodeList(last or {}) }, ";")
end

-- A shared value -> { month, all, this, lastMonth, last }, or nil.
function HF.Decode(v)
    if not v or v == "" then return nil end
    local parts = ns.Split(v, ";")
    if parts[1] ~= HF.VERSION then return nil end
    return { month = tonumber(parts[2]) or 0, all = DecodeList(parts[3]), this = DecodeList(parts[4]),
             lastMonth = tonumber(parts[5]) or 0, last = DecodeList(parts[6]) }
end

------------------------------------------------------------------------
-- Plausibility. The game only lets an addon read its own player's
-- statistics, so guildmates' numbers can't be checked against the game. The
-- sync already stops anyone sending numbers for someone else (a record must
-- come from its own member); these limits stop a modified copy from lying
-- big about its own. Each statistic has a generous ceiling per day of play
-- (`rate`): all-time numbers can't beat it since WoW: Forever opened
-- (HF.LAUNCH; Social Butterfly since it began counting), a month's can't beat
-- 31 days of it, and no month can beat all time. A record that breaks any of
-- them is left out of the Hall of Fame altogether.
------------------------------------------------------------------------
HF.LAUNCH = 1788220800 -- 1 Sep 2026, before WoW: Forever opened
HF.MONTH_DAYS = 31

function HF.Plausible(r, now)
    now = now or (ns.DB and ns.DB.Now and ns.DB:Now()) or time()
    if not r then return false end
    if r.month < 202609 or r.month > HF.Month(now + 86400) then return false end
    for _, s in ipairs(HF.STATS) do
        if s.rate then
            local days = math.max(1, (now - (s.since or HF.LAUNCH)) / 86400 + 1)
            local all, this, last = r.all[s.key], r.this[s.key], r.last[s.key]
            if all and all > s.rate * days then return false end
            for _, v in ipairs({ this or 0, last or 0 }) do
                if v > s.rate * HF.MONTH_DAYS then return false end
                if v > 0 and v > (all or 0) then return false end
            end
        end
    end
    return true
end

-- Members whose shared numbers break the limits (for the tab's note).
function HF:Implausible(full)
    local r = HF.Decode(ns.Sync:Value("HF:" .. full))
    return r ~= nil and not HF.Plausible(r)
end

------------------------------------------------------------------------
-- Officers can leave a member out (HX:<member> = "1"), e.g. numbers that
-- look wrong but stay inside the limits. Shared and audited.
------------------------------------------------------------------------
function HF:Hidden(full)
    return (ns.Sync:Value("HX:" .. full) or "") ~= ""
end

function HF:CanHide()
    return ns.Sync:CanWrite("HX:" .. (Me() or "x"))
end

function HF:SetHidden(full, hidden)
    return ns.Sync:Set("HX:" .. full, hidden and "1" or "")
end

function HF:Publish()
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    local cur = self:ReadMine()
    if not cur then return end
    self.dirty = false
    local month = HF.Month()
    local state = MyState()
    local this, last = HF.Advance(state, cur, month)
    local value = HF.Encode(month, cur, this, state.lastMonth, last)
    local key = "HF:" .. Me()
    if (ns.Sync:Value(key) or "") ~= value then ns.Sync:Set(key, value) end
end

-- A character's numbers for a period ("all", "month" or "last"), as of
-- now: { key = n }, or nil when they don't share any.
function HF:For(full, period, nowMonth)
    local r = HF.Decode(ns.Sync:Value("HF:" .. full))
    if not r then return nil end
    if not HF.Plausible(r) then return nil end
    if period == "all" then return r.all end
    nowMonth = nowMonth or HF.Month()
    if period == "month" then
        return r.month == nowMonth and r.this or {}
    end
    -- last month: what they had then, from a record written then or since
    local want = HF.PrevMonth(nowMonth)
    if r.month == nowMonth then return r.lastMonth == want and r.last or {} end
    if r.month == want then return r.this end
    return {}
end

------------------------------------------------------------------------
-- Leaderboards (shared by the Hall of Fame tab and the champions)
------------------------------------------------------------------------
-- Every guildmate's numbers for a period, one entry per person: their main
-- and alts are added up (a person counts once on every card, their time and
-- kills add together). Members left out by officers or whose numbers break
-- the limits aren't listed.
-- { people, sharing, noAddon, hidden, flagged, totals, boards = { key = { { e, n, key }... } } }
function HF:Boards(period, month)
    month = month or HF.Month()
    local groups, order = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        local key = e.main or e.full
        local g = groups[key]
        if not g then
            g = { chars = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        g.chars[#g.chars + 1] = e
        if e.full == key then g.e = e end
    end
    local wins = self:Wins(period, month)
    local boards, totals, sharing, noAddon, hidden, flagged = {}, {}, 0, 0, 0, 0
    for _, s in ipairs(self.STATS) do boards[s.key] = {} end
    for _, key in ipairs(order) do
        local g = groups[key]
        g.e = g.e or g.chars[1] -- main not in the guild: their first alt
        local sum, any, hasAddon, isHidden, isFlagged = {}, false, false, false, false
        for _, c in ipairs(g.chars) do
            if c.hasAddon then hasAddon = true end
            if self:Hidden(c.full) then isHidden = true end
            if self:Implausible(c.full) then isFlagged = true end
        end
        if isHidden then
            hidden = hidden + 1
        elseif isFlagged then
            flagged = flagged + 1
        else
            for _, c in ipairs(g.chars) do
                local t = self:For(c.full, period, month)
                if t then
                    any = true
                    for k, n in pairs(t) do sum[k] = (sum[k] or 0) + n end
                end
            end
            sum.champs = wins[key]
            if sum.champs then any = true end
        end
        if not hasAddon then noAddon = noAddon + 1 end
        if any then
            sharing = sharing + 1
            for k, n in pairs(sum) do
                if n > 0 and boards[k] then
                    table.insert(boards[k], { e = g.e, n = n, key = key })
                    totals[k] = (totals[k] or 0) + n
                end
            end
        end
    end
    for _, list in pairs(boards) do
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.e.short < b.e.short
        end)
    end
    return { people = #order, sharing = sharing, noAddon = noAddon, hidden = hidden, flagged = flagged,
             totals = totals, boards = boards }
end

-- Last month's champion of each card: winner takes all, and a tie makes
-- everyone at the top a champion. { key = { n = best, winners = { { e, n, key }... } } }
function HF:Champions(month)
    month = month or HF.Month()
    local data = self:Boards("last", month)
    local out = {}
    for _, s in ipairs(self.STATS) do
        if not s.noChampion then
            local list = data.boards[s.key]
            local top = list[1] and list[1].n or 0
            if top > 0 then
                local winners = {}
                for _, p in ipairs(list) do
                    if p.n == top then winners[#winners + 1] = p else break end
                end
                out[s.key] = { n = top, winners = winners }
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Champion titles, recorded by officers (HW:<month> = "quests=Name,Name;kills=Name")
-- On the 2nd of a month (a day for everyone's numbers for the month before
-- to arrive) the first officer's copy online writes down that
-- month's champions. Only officers may write it, so a modified copy can't
-- give itself titles; Most Champion Wins counts these records.
------------------------------------------------------------------------
HF.RECORD_ON_DAY = 2 -- UTC day of the month: a day's lag so last month's numbers are all in

-- A guild using NGM Peon (GS:peon = "1", brought in with /ngm peon): NGM
-- Peon crowns the champions from Blizzard's numbers for everyone, and the
-- addon shows those (HW records in its code) instead of crowning its own,
-- so the game and Discord never name different winners.
function HF:PeonCrowns()
    return ns.Sync:Value("GS:peon") == "1"
end

function HF.EncodeChampions(champs)
    local parts = {}
    for _, s in ipairs(HF.STATS) do
        local c = champs[s.key]
        if c then
            local names = {}
            for i, p in ipairs(c.winners) do names[i] = p.key end
            parts[#parts + 1] = s.key .. "=" .. table.concat(names, ",")
        end
    end
    return table.concat(parts, ";")
end

-- "quests=A,B;kills=C" -> { quests = { "A", "B" }, kills = { "C" } }
function HF.DecodeChampions(v)
    local out = {}
    for k, names in (v or ""):gmatch("(%w+)=([^;]*)") do
        if HF.BY_KEY[k] and not HF.BY_KEY[k].noChampion then
            out[k] = {}
            for n in names:gmatch("[^,]+") do out[k][#out[k] + 1] = n end
        end
    end
    return out
end

function HF:RecordChampions(now)
    now = now or ns.DB:Now()
    if not (ns.IsOfficer() and ns.Sync.readyFor) or self:PeonCrowns() then return false end
    if tonumber(date("!%d", now)) < self.RECORD_ON_DAY then return false end
    local last = HF.PrevMonth(HF.Month(now))
    local key = "HW:" .. last
    if ns.Sync:Get(key) then return self:Recount(now) end -- already crowned: maybe a recount
    local champs = self:Champions(HF.Month(now))
    if not next(champs) then return false end
    local ok = ns.Sync:Set(key, HF.EncodeChampions(champs))
    if ok then
        -- your copy crowned them: tell you they're ready to announce
        ns:Print(((ns.GOLD .. "%s's Hall of Fame champions have been crowned!|r You can now announce the winners: ")
            .. ("|cffffffff/ngm hof|r, then " .. ns.GOLD .. "Announce Champions|r.")):format(HF.MonthName(last)))
    end
    return ok
end

-- Recount: for a day after crowning (until 00:00 UTC on the 3rd), late
-- numbers can still change a winner. A category only changes when someone
-- not crowned has caught up with or passed the crowned number, so an officer
-- whose copy is missing numbers (which only ever makes them lower) can never
-- undo another officer's correction. The officer whose copy corrects it is
-- told, so they can announce the correction.
HF.RECOUNT = 86400

function HF:InRecount(now)
    now = now or ns.DB:Now()
    local at = HF.CrownTime(HF.Month(now))
    return now >= at and now < at + self.RECOUNT
end

function HF:Recount(now)
    now = now or ns.DB:Now()
    if not (ns.IsOfficer() and ns.Sync.readyFor and self:InRecount(now)) or self:PeonCrowns() then return false end
    local month = HF.Month(now)
    local last = HF.PrevMonth(month)
    local key = "HW:" .. last
    local rec = ns.Sync:Get(key)
    if not rec then return false end
    local recorded = HF.DecodeChampions(rec.v)
    local live = self:Champions(month)
    local data = self:Boards("last", month)
    local changed, notes = false, {}
    local final = {}
    for _, s in ipairs(self.STATS) do
        if not s.noChampion then
            local names = recorded[s.key] or {}
            local crownedN = -1
            local isWinner = {}
            for _, n in ipairs(names) do
                isWinner[n] = true
                for _, p in ipairs(data.boards[s.key] or {}) do
                    if p.key == n and p.n > crownedN then crownedN = p.n end
                end
            end
            -- crowned, but this copy has no numbers for any of the winners:
            -- it can't judge, so it leaves the category alone
            local caught = false
            if #names == 0 or crownedN >= 0 then
                for _, p in ipairs(data.boards[s.key] or {}) do
                    if not isWinner[p.key] and p.n > 0 and p.n >= crownedN then caught = true break end
                end
            end
            if caught and live[s.key] then
                final[s.key] = live[s.key]
                local was, now_ = {}, {}
                for i, n in ipairs(names) do was[i] = ns.ShortName(n) end
                for i, p in ipairs(live[s.key].winners) do now_[i] = ns.ShortName(p.key) end
                local w, nw = table.concat(was, " & "), table.concat(now_, " & ")
                if w ~= nw then
                    changed = true
                    notes[#notes + 1] = ("%s: %s (was %s)"):format(s.label, nw, w ~= "" and w or "nobody")
                end
            elseif #names > 0 then
                local winners = {}
                for i, n in ipairs(names) do winners[i] = { key = n } end
                final[s.key] = { winners = winners }
            end
        end
    end
    if not changed then return false end
    local ok = ns.Sync:Set(key, HF.EncodeChampions(final))
    if ok then
        ns:Print(((ns.GOLD .. "Recount:|r late numbers changed %s's Hall of Fame champions. %s. You may want to announce the correction (|cffffffff/ngm hof|r, " .. ns.GOLD .. "Announce Champions|r).")):format(
            HF.MonthName(last), table.concat(notes, "; ")))
    end
    return ok
end

-- Titles per person for a period: "all" (every recorded month), "month"
-- (titles handed out this month, i.e. last month's champions) or "last".
-- { [person] = count }
function HF:Wins(period, month)
    month = month or HF.Month()
    local want
    if period == "month" then want = HF.PrevMonth(month)
    elseif period == "last" then want = HF.PrevMonth(HF.PrevMonth(month)) end
    local out = {}
    for key, rec in pairs(ns.Sync:Store("guild") or {}) do
        local m = key:match("^HW:(%d+)$")
        if m and (not want or tonumber(m) == want) then
            for _, names in pairs(HF.DecodeChampions(rec.v)) do
                for _, n in ipairs(names) do out[n] = (out[n] or 0) + 1 end
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Social Butterfly: time in guild chat conversations
-- The day is cut into 15-minute blocks. A block counts when you said
-- something in guild chat AND another guildmate did too (talking to
-- yourself doesn't count), at most 8 blocks per (UTC) day. Ten messages in a
-- row count once, so spamming gets nothing. Kept per character on this
-- computer: Settings().hof[character].social = { total, day, today, block, me, them, counted }.
------------------------------------------------------------------------
HF.SOCIAL_BLOCK = 900
HF.SOCIAL_DAY_CAP = 8

local function SocialState()
    local st = MyState()
    st.social = st.social or { total = 0 }
    return st.social
end

-- `fromMe`: you said it; otherwise a guildmate did. `now` for tests.
function HF:SocialNote(fromMe, now)
    now = now or time()
    local s = SocialState()
    local block = math.floor(now / self.SOCIAL_BLOCK)
    if s.block ~= block then
        s.block, s.me, s.them, s.counted = block, false, false, false
    end
    local day = tonumber(date("!%Y%m%d", now))
    if s.day ~= day then s.day, s.today = day, 0 end
    if fromMe then s.me = true else s.them = true end
    if s.me and s.them and not s.counted and (s.today or 0) < self.SOCIAL_DAY_CAP then
        s.counted = true
        s.today = (s.today or 0) + 1
        s.total = (s.total or 0) + 1
        self.dirty = true
    end
end

function HF:SocialTotal()
    local me = Me()
    local st = me and (ns.DB:Settings().hof or {})[me]
    return st and st.social and st.social.total or 0
end

function HF:OnGuildChat(_, _, sender)
    if issecretvalue and issecretvalue(sender) then return end
    local who = ns.NormalizeName(sender)
    if not who then return end
    self:SocialNote(who == Me())
end

------------------------------------------------------------------------
-- When champions are crowned: 00:00 UTC on the 2nd of each month.
------------------------------------------------------------------------
-- Seconds since 1970 for a UTC date (no time zone involved).
local function UTCDay(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400
end
HF.UTCDay = UTCDay

-- When `month`'s champions-of-the-month-before are crowned.
function HF.CrownTime(month)
    return UTCDay(math.floor(month / 100), month % 100, HF.RECORD_ON_DAY)
end

-- Where the crowning stands now:
-- { state = "waiting" | "tallying" | "due" | "crowned", won = month being
--   judged, at = crowning time (this month's), nextAt = the next one }
-- tallying: the month is over, champions are crowned at `at`;
-- due: crowning time has passed but no officer's addon has recorded them yet.
function HF:CrownStatus(now)
    now = now or ns.DB:Now()
    local month = HF.Month(now)
    local won = HF.PrevMonth(month)
    local at = HF.CrownTime(month)
    local y, m = math.floor(month / 100), month % 100
    local nextMonth = (m == 12) and ((y + 1) * 100 + 1) or (month + 1)
    local nextAt = HF.CrownTime(nextMonth)
    local recorded = ns.Sync:Get("HW:" .. won) ~= nil
    if recorded then
        return { state = "crowned", won = won, at = at, nextAt = nextAt, nextWon = month }
    end
    if now < at then
        return { state = "tallying", won = won, at = at, nextAt = at, nextWon = won }
    end
    -- a month with nobody's numbers never gets a record: treat it as crowned
    if not next(self:Champions(month)) then
        return { state = "waiting", won = won, at = at, nextAt = nextAt, nextWon = month }
    end
    return { state = "due", won = won, at = at, nextAt = nextAt, nextWon = month }
end

-- The champions officers recorded for last month, in HF:Champions' shape
-- (each winner with their number for that month), or nil before they're
-- recorded. Cards show these, so they always match the titles.
function HF:RecordedChampions(month)
    month = month or HF.Month()
    local rec = ns.Sync:Get("HW:" .. HF.PrevMonth(month))
    if not rec then return nil end
    local data = self:Boards("last", month)
    local out = {}
    for key, names in pairs(HF.DecodeChampions(rec.v)) do
        local winners, best = {}, 0
        for _, name in ipairs(names) do
            local p
            for _, q in ipairs(data.boards[key] or {}) do
                if q.key == name then p = q break end
            end
            local e = ns.Roster.byName[name]
            if not p and e then p = { e = e, n = 0, key = name } end
            if p then
                winners[#winners + 1] = p
                if p.n > best then best = p.n end
            end
        end
        if #winners > 0 then out[key] = { n = best, winners = winners } end
    end
    return out
end

------------------------------------------------------------------------
-- Champion titles: last month's recorded champions hold them all month.
------------------------------------------------------------------------
HF.MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July",
                   "August", "September", "October", "November", "December" }

function HF.MonthName(m)
    return HF.MONTH_NAMES[m % 100] or tostring(m)
end

-- The titles `full`'s person holds this month: list of stat labels, and the
-- month they were won in. Empty until officers have recorded them (the 2nd).
function HF:TitlesFor(full, month)
    month = month or HF.Month()
    local e = full and ns.Roster.byName[full]
    local person = e and (e.main or e.full) or full
    local won = HF.PrevMonth(month)
    local out = {}
    local rec = person and ns.Sync:Get("HW:" .. won)
    if not rec then return out, won end
    local champs = HF.DecodeChampions(rec.v)
    for _, s in ipairs(self.STATS) do
        for _, n in ipairs(champs[s.key] or {}) do
            if n == person then out[#out + 1] = s.label break end
        end
    end
    return out, won
end

-- "November's Champion: Quests completed, Kills" (gold), or nil.
function HF:TitleText(full)
    local titles, won = self:TitlesFor(full)
    if #titles == 0 then return nil end
    return ((ns.GOLD .. "%s's Champion:|r %s")):format(HF.MonthName(won), table.concat(titles, ", "))
end

------------------------------------------------------------------------
-- Announcing the champions in guild chat (officers, by click)
-- HA:<month> = "<time>" remembers who last announced that month's champions
-- (the record's author), shared so every officer can see it.
------------------------------------------------------------------------
HF.CHAT_MAX = 255

-- Guild chat lines for `won`'s champions (people's short names), each under 255.
function HF:AnnounceLines(won)
    local rec = ns.Sync:Get("HW:" .. won)
    if not rec then return nil end
    local champs = HF.DecodeChampions(rec.v)
    local parts = {}
    for _, s in ipairs(self.STATS) do
        -- only current guildmates' names go into guild chat
        local short = {}
        for _, n in ipairs(champs[s.key] or {}) do
            local e = ns.Roster.byName[n]
            if e then short[#short + 1] = e.short end
        end
        if #short > 0 then parts[#parts + 1] = s.label .. ": " .. table.concat(short, " & ") end
    end
    if #parts == 0 then return nil end
    local lines = {}
    local cur = ("Congrats to %s's Hall of Fame champions! "):format(HF.MonthName(won))
    for i, part in ipairs(parts) do
        local piece = part .. (i < #parts and "; " or ".")
        if #cur + #piece > self.CHAT_MAX then
            lines[#lines + 1] = ns.Trim(cur)
            cur = ""
        end
        cur = cur .. piece
    end
    lines[#lines + 1] = ns.Trim(cur)
    return lines
end

function HF:LastAnnounced(won)
    local rec = ns.Sync:Get("HA:" .. won)
    if not rec or (rec.v or "") == "" then return nil end
    return rec.t, rec.a
end

-- The announcement's state for the Announce tooltip, the same on every
-- officer's copy (both records are shared): { text, r, g, b } or nil.
--   "Last announced 2 Dec, 7 pm by Shawn."
--   "Corrected 2 Dec, 9 pm by Marc, AFTER Shawn last announced on 2 Dec, 7 pm. Announce again to post the correction."
function HF:AnnounceStatus(won)
    local t, by = self:LastAnnounced(won)
    if not t then return nil end
    local when = (ns.HallOfFameView and ns.HallOfFameView.When) or ns.FormatAgo
    local crowned = ns.Sync:Get("HW:" .. won)
    if crowned and crowned.t > t then
        return { text = ("Corrected %s by %s, AFTER %s last announced on %s. Announce again to post the correction."):format(
            when(crowned.t), ns.ShortName(crowned.a or "?"), ns.ShortName(by or "?"), when(t)), r = 1, g = 0.5, b = 0.3 }
    end
    return { text = ("Last announced %s by %s."):format(when(t), ns.ShortName(by or "?")), r = 0.6, g = 0.6, b = 0.6 }
end

function HF:CanAnnounce()
    return ns.IsOfficer() and ns.Sync:CanWrite("HA:" .. HF.PrevMonth(HF.Month()))
end

-- Sends the lines to guild chat (call from a click). true, or false and why.
function HF:Announce()
    local won = HF.PrevMonth(HF.Month())
    if not self:CanAnnounce() then return false, "Officers only." end
    local lines = self:AnnounceLines(won)
    if not lines then return false, "Last month's champions aren't recorded yet (an officer's addon does it on the 2nd)." end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do send(line, "GUILD") end
    ns.Sync:Set("HA:" .. won, tostring(ns.DB:Now()))
    return true
end

function HF:Init()
    -- the statistics change with nearly every kill: note it, and share at
    -- most every 10 minutes
    ns:RegisterEvent("CRITERIA_UPDATE", function() HF.dirty = true end)
    ns:RegisterEvent("CHAT_MSG_GUILD", function(...) HF:OnGuildChat(...) end)
    local publish = ns.Safe(function() HF:Publish() end, "HallOfFame")
    C_Timer.After(30, publish)
    -- officers: last month's champions, once guildmates' numbers have synced
    local record = ns.Safe(function() HF:RecordChampions() end, "HallOfFame")
    -- 2 to 3 minutes after login (staggered, so two officers logging in
    -- together don't both crown: the first one's record reaches the other)
    C_Timer.After(120 + math.random() * 60, record)
    C_Timer.NewTicker(3600, record)
    -- recount day: re-check soon after guildmates' late numbers arrive
    ns:On("HALL_OF_FAME_CHANGED", function()
        if ns.IsOfficer() and HF:InRecount() then ns.Debounce("hofrecount", 60, record) end
    end)
    C_Timer.NewTicker(self.PUBLISH_EVERY, function() if HF.dirty then publish() end end)
end
