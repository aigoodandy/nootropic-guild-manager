--[[
    Nootropic Guild Manager - Database
    SavedVariables (NootropicGuildManagerDB):

      settings = { minimap, iconStyle, communitiesButton, titleUseGuild,
                   auditDays, onlineOnly, sortKey, sortAsc, hiddenColumns,
                   columnWidths, frameSize, framePos }
      guilds["<Guild>-<Realm>"] = {
          syncVersion = 2,
          sync    = { guild = { [key] = record }, officer = { ... } }, -- see Core/Sync.lua
          members = { ["Name-Realm"] = { note = "private, never shared", + fields built from sync records } },
          recruit = { ... },                                           -- see Services/Recruit.lua
      }

    Shared data (tags, links, specs, professions, officer log) is
    written through ns.Sync, which checks permissions, versions, broadcasts
    and audits each change. Setters return true, or nil plus an error.
]]
local _, ns = ...
local DB = {}
ns.DB = DB

local DEFAULTS = {
    version = 1,
    settings = {
        minimap = { angle = 200, hide = false, left = "roster", right = "options", shift = "recruit" },
        iconStyle = "mug",           -- "mug" | "stein" | "emblem"
        communitiesButton = true,    -- shortcut on the Guild & Communities window
        blizzRoster = true,          -- tags, alts and tooltips on the game's guild roster
        titleUseGuild = false,       -- window title: "<Guild> Guild Manager"
        showAddonCount = true,       -- "x using ... Guild Manager" at the bottom of the window
        whoWhisperButton = true,     -- recruitment whisper button on the game's /who results
        auditDays = 30,              -- audit history kept: 30, 60 or 90 days
        onlineOnly = false,
        sortKey = "rank",
        sortAsc = true,
        -- the game's own roster already shows level, class, zone and rank
        hiddenColumns = { version = true, second = true, level = true, class = true, zone = true, rank = true }, -- false = shown on purpose
        columnWidths = {},
        frameSize = { w = 1000, h = 580 },
    },
    guilds = {},
}

local function ApplyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function DB:Init()
    NootropicGuildManagerDB = NootropicGuildManagerDB or {}
    local sv = NootropicGuildManagerDB
    ApplyDefaults(DEFAULTS, sv)
    -- 2.0: settings of removed features
    local st = sv.settings
    st.ratingHiddenOnce, st.hiddenColumns.rating = nil, nil
    st.tabSide, st.compact, st.miniPos, st.export = nil, nil, nil, nil
    st.shareLocation, st.showOnMap, st.customDots = nil, nil, nil
    st.reviewed, st.kudosGiven = nil, nil
    sv.inspectLog = nil
    for _, mine in pairs(st.schedules or {}) do mine.days = nil end
    for _, g in pairs(sv.guilds) do
        g.myGoals, g.myStats, g.goalHistory, g.pollsSeen = nil, nil, nil, nil
        g.kudosOutbox, g.reviewOutbox = nil, nil
    end
    self.sv = sv
end

function DB:Settings()
    return self.sv.settings
end

function DB:Now()
    return (GetServerTime and GetServerTime()) or time()
end

------------------------------------------------------------------------
-- Guild scope
------------------------------------------------------------------------
function DB:GuildKey()
    if not IsInGuild() then return nil end
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" then return nil end
    if not realm or realm == "" then realm = ns.PlayerRealm() end
    return name .. "-" .. realm
end

function DB:Guild()
    local key = self:GuildKey()
    if not key then return nil end
    local g = self.sv.guilds[key]
    if not g then
        g = { members = {}, syncVersion = 2, sync = { guild = {}, officer = {} } }
        self.sv.guilds[key] = g
        self.tagCache = nil
        ns.Sync:SeedDefaults()
    end
    return g
end

------------------------------------------------------------------------
-- Tags (shared; officers manage them)
------------------------------------------------------------------------
local EMPTY = {}

function DB:InvalidateTags()
    self.tagCache = nil
end

-- Active tags in display order.
function DB:GetTags()
    local g = self:Guild()
    if not g then return EMPTY end
    if self.tagCache and self.tagCacheFor == g then return self.tagCache end
    local list = {}
    for key, rec in pairs(ns.Sync:Store("guild")) do
        if key:sub(1, 2) == "T:" then
            local def = ns.Sync.Codec.ParseTagDef(rec.v)
            if def and not def.deleted then
                def.id = key:sub(3)
                def.icon = ns.Data:ParseIcon(ns.Sync:Value("TI:" .. def.id))
                list[#list + 1] = def
            end
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name:lower() < b.name:lower()
    end)
    self.tagCache, self.tagCacheFor = list, g
    return list
end

function DB:GetTag(id)
    for _, tag in ipairs(self:GetTags()) do
        if tag.id == id then return tag end
    end
end

function DB:FindTagByName(name)
    local lower = name:lower()
    for _, tag in ipairs(self:GetTags()) do
        if tag.name:lower() == lower then return tag end
    end
end

function DB:CanManageTags()
    return self:HasPerm("tags")
end

local function ValidateTagName(name)
    name = ns.Trim(name):gsub("[|\n\t;]", "")
    if name == "" then return nil, "Tag name cannot be empty." end
    if #name > ns.Data.MAX_TAG_LENGTH then
        return nil, ("Tag names are limited to %d characters."):format(ns.Data.MAX_TAG_LENGTH)
    end
    return name
end

local function SaveTag(id, color, order, deleted, name)
    return ns.Sync:Set("T:" .. id, ns.Sync.Codec.TagDef(color, order, deleted, name))
end

function DB:CreateTag(name, color, icon)
    if not self:Guild() then return nil, "You are not in a guild." end
    if not self:CanManageTags() then return nil, "Your rank can't manage tags." end
    local clean, err = ValidateTagName(name)
    if not clean then return nil, err end
    if self:FindTagByName(clean) then
        return nil, ("A tag named \"%s\" already exists."):format(clean)
    end
    local tags = self:GetTags()
    local order = (#tags > 0 and tags[#tags].order or 0) + 10
    local id = "c" .. ns.Sync.Base36(self:Now()) .. ns.Sync.Base36(math.random(0, 1295))
    color = color or ns.Data:NextColor(#tags)
    local ok, serr = SaveTag(id, color, order, false, clean)
    if not ok then return nil, serr end
    if icon then self:SetTagIcon(id, icon) end
    return self:GetTag(id)
end

function DB:SetTagIcon(id, icon)
    if not self:GetTag(id) then return nil, "Tag not found." end
    return ns.Sync:Set("TI:" .. id, tostring(icon or ""))
end

-- Saves the tag editor: name, color and icon in one go.
function DB:UpdateTag(id, name, color, icon)
    local tag = self:GetTag(id)
    if not tag then return nil, "Tag not found." end
    if name ~= tag.name then
        local ok, err = self:RenameTag(id, name)
        if not ok then return nil, err end
    end
    if color and color ~= tag.color then
        local ok, err = self:SetTagColor(id, color)
        if not ok then return nil, err end
    end
    if icon and icon ~= tag.icon then
        local ok, err = self:SetTagIcon(id, icon)
        if not ok then return nil, err end
    end
    return self:GetTag(id)
end

function DB:RenameTag(id, name)
    local tag = self:GetTag(id)
    if not tag then return nil, "Tag not found." end
    local clean, err = ValidateTagName(name)
    if not clean then return nil, err end
    local existing = self:FindTagByName(clean)
    if existing and existing.id ~= id then
        return nil, ("A tag named \"%s\" already exists."):format(clean)
    end
    local ok, serr = SaveTag(id, tag.color, tag.order, false, clean)
    if not ok then return nil, serr end
    return self:GetTag(id)
end

function DB:SetTagColor(id, color)
    local tag = self:GetTag(id)
    if not tag then return nil, "Tag not found." end
    return SaveTag(id, color, tag.order, false, tag.name)
end

function DB:MoveTag(id, delta)
    local tags = self:GetTags()
    for i, tag in ipairs(tags) do
        if tag.id == id then
            local other = tags[i + delta]
            if not other then return end
            local a, b = tag.order, other.order
            if a == b then b = a + delta end
            local ok, err = SaveTag(tag.id, tag.color, b, false, tag.name)
            if not ok then return nil, err end
            return SaveTag(other.id, other.color, a, false, other.name)
        end
    end
end

function DB:DeleteTag(id)
    local tag = self:GetTag(id)
    if not tag then return nil, "Tag not found." end
    return SaveTag(id, tag.color, tag.order, true, tag.name)
end

------------------------------------------------------------------------
-- Guild-wide settings (shared; officers change them)
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Permissions: the Guild Master picks which ranks may do each of these
-- (Options > Officers > Permissions). GS:perm_<key> = "" (the default:
-- officers, i.e. ranks that can read officer notes; everyone for recruit)
-- or rank numbers "1,3,4" ("-" = nobody but the Guild Master). The Guild Master (rank 0) always may, and only they change
-- these. Officer-only data (officer log, audit, officer stats) can't be
-- handed out: the game only delivers it to officer ranks.
------------------------------------------------------------------------
DB.PERMS = {
    { key = "tags",      label = "Manage the tag list",               hint = "Create, rename, recolor, reorder and delete tags (Tags tab)." },
    { key = "tagothers", label = "Tag other guildmates",              hint = "Everyone can always tag themselves." },
    { key = "links",     label = "Link mains and alts",               hint = "Mark alts, change mains, unlink." },
    { key = "recruit",   label = "Recruit",                           everyone = true,
      hint = "The Recruitment tab and the /who whisper button: search, whisper and invite." },
    { key = "profiles",  label = "Edit other guildmates' profiles",   hint = "Spec, roles, professions and contact info. Everyone can always edit their own." },
}
DB.PERM_BY_TYPE = { T = "tags", TI = "tags", MT = "tagothers", M = "links",
    MS = "profiles", RL = "profiles", MP = "profiles", CN = "profiles" }

-- { [rankIndex] = true }, or nil for the default (officers).
function DB:PermRanks(key)
    local v = ns.Sync:Value("GS:perm_" .. key)
    if not v or v == "" then return nil end
    local set = {}
    for n in v:gmatch("%d+") do set[tonumber(n)] = true end
    return set
end

function DB:IsGuildMaster()
    return IsInGuild() and self:MyRankIndex() == 0
end

-- May you do `key`? (the Guild Master always may)
function DB:PermDef(key)
    for _, p in ipairs(self.PERMS) do if p.key == key then return p end end
end

function DB:HasPerm(key)
    if not IsInGuild() then return false end
    local rank = self:MyRankIndex()
    if rank == 0 then return true end
    local set = self:PermRanks(key)
    if not set then
        local def = self:PermDef(key)
        return (def and def.everyone) and true or ns.IsOfficer()
    end
    return rank ~= nil and set[rank] == true
end

-- set = { [rankIndex] = true } or nil for the default (officers).
function DB:SetPermRanks(key, set)
    if not self:IsGuildMaster() then return nil, "Only the Guild Master can change permissions." end
    local list = {}
    for n in pairs(set or {}) do if n ~= 0 then list[#list + 1] = n end end
    table.sort(list)
    local v = set and table.concat(list, ",") or ""
    if set and v == "" then v = "-" end -- nobody but the Guild Master
    return ns.Sync:Set("GS:perm_" .. key, v)
end

-- The default's name: "Everyone" or "Officers".
function DB:PermDefaultText(key)
    local def = self:PermDef(key)
    return (def and def.everyone) and "Everyone" or "Officers"
end

-- "Officers (default)", "Guild Master only" or "Veteran, Officer".
function DB:PermText(key)
    local set = self:PermRanks(key)
    if not set then return self:PermDefaultText(key) .. " (default)" end
    local names = {}
    for _, r in ipairs(self:GuildRanks()) do
        if r.index ~= 0 and set[r.index] then names[#names + 1] = r.name end
    end
    if #names == 0 then return "Guild Master only" end
    return table.concat(names, ", ")
end

-- Your rank number in the guild (0 = Guild Master), or nil.
function DB:MyRankIndex()
    if not IsInGuild() then return nil end
    local _, _, index = GetGuildInfo("player")
    return index
end

-- The guild's ranks: { { index = 0, name = "Guild Master" }, ... }
function DB:GuildRanks()
    local out = {}
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 1, n do
        out[#out + 1] = { index = i - 1, name = GuildControlGetRankName(i) or ("Rank " .. i) }
    end
    return out
end

------------------------------------------------------------------------
-- Members
------------------------------------------------------------------------
function DB:GetMember(full)
    local g = self:Guild()
    return g and full and g.members[full]
end

function DB:EnsureMember(full)
    local g = self:Guild()
    if not g or not full then return nil end
    local m = g.members[full]
    if not m then
        m = { tags = {} }
        g.members[full] = m
    end
    m.tags = m.tags or {}
    return m
end

-- Who may edit what on a character's profile.
function DB:CanEditTags(full) return ns.Sync:CanWrite("MT:" .. full) end
function DB:CanEditProfile(full) return ns.Sync:CanWrite("MS:" .. full) end
function DB:CanEditLinks() return self:HasPerm("links") end

function DB:SetTag(full, id, state)
    local m = self:EnsureMember(full)
    if not m then return nil, "You are not in a guild." end
    local set = {}
    for tagId in pairs(m.tags or {}) do set[tagId] = true end
    if state == nil then state = not set[id] end
    set[id] = state and true or nil
    return ns.Sync:Set("MT:" .. full, ns.Sync.Codec.Set(set))
end

-- Private notes never leave this computer.
function DB:SetNote(full, text)
    local m = self:EnsureMember(full)
    if not m then return end
    text = ns.Trim(text)
    if text == "" then text = nil end
    if m.note == text then return end
    m.note = text
    ns:Fire("MEMBER_CHANGED", full)
end

-- Roles: { tank = true, ... } (the member, or officers)
function DB:SetRoles(full, set)
    local list = {}
    for _, r in ipairs(ns.Data.ROLES) do
        if set and set[r.key] then list[#list + 1] = r.key end
    end
    return ns.Sync:Set("RL:" .. full, table.concat(list, ","))
end

function DB:SetManualSpec(full, spec)
    spec = spec and ns.Trim(spec) or ""
    return ns.Sync:Set("MS:" .. full, spec)
end

local function FindProf(list, name)
    if not list then return end
    local lower = name:lower()
    for i, p in ipairs(list) do
        if p.name:lower() == lower then return p, i end
    end
end

local function SaveProfs(full, list)
    return ns.Sync:Set("MP:" .. full, ns.Sync.Codec.Profs(list))
end

local function CopyProfs(full)
    local m = DB:GetMember(full)
    local list = {}
    for _, p in ipairs(m and m.profs or {}) do list[#list + 1] = { name = p.name, rank = p.rank } end
    return list
end

function DB:AddManualProf(full, name)
    if not name or name == "" then return end
    local list = CopyProfs(full)
    if FindProf(list, name) then return true end
    table.insert(list, { name = name, rank = 0 })
    return SaveProfs(full, list)
end

function DB:SetManualProfRank(full, name, rank)
    local list = CopyProfs(full)
    local p = FindProf(list, name)
    if not p then return end
    p.rank = math.max(0, math.min(999, math.floor(tonumber(rank) or 0)))
    return SaveProfs(full, list)
end

function DB:RemoveManualProf(full, name)
    local list = CopyProfs(full)
    local _, i = FindProf(list, name)
    if not i then return end
    table.remove(list, i)
    return SaveProfs(full, list)
end

------------------------------------------------------------------------
-- Mains and alts (shared; officers only)
-- Only alts store a link. A main's alts are everyone pointing at it, so
-- editing either side keeps both in sync. Links always point at the
-- top-level main, never at another alt.
------------------------------------------------------------------------
function DB:GetMainOf(full)
    local m = self:GetMember(full)
    return m and m.main
end

function DB:GetAltsOf(full)
    local out = {}
    local g = self:Guild()
    if not g or not full then return out end
    for name, m in pairs(g.members) do
        if m.main == full then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function DB:RootOf(full)
    local seen = {}
    while full and not seen[full] do
        seen[full] = true
        local m = self:GetMember(full)
        if not (m and m.main) then return full end
        full = m.main
    end
    return full
end

local function Link(alt, main)
    return ns.Sync:Set("M:" .. alt, main or "")
end

-- Marks `alt` as an alt of `main`. If `main` is currently one of alt's own
-- alts, `main` is promoted to lead the whole family instead.
function DB:SetMain(alt, main)
    if not alt or not main then return nil, "Pick a character." end
    if alt == main then return nil, "A character can't be its own alt." end
    if not self:Guild() then return nil, "You are not in a guild." end
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    local root = self:RootOf(main)
    if root == alt then return self:MakeMain(main) end
    local family = self:GetAltsOf(alt)
    local ok, err = Link(alt, root)
    if not ok then return nil, err end
    for _, a in ipairs(family) do Link(a, root) end
    return true
end

function DB:ClearMain(alt)
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    if self:GetMainOf(alt) then return Link(alt, nil) end
    return true
end

-- Makes `full` the main of its family (its old main becomes an alt).
function DB:MakeMain(full)
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    local root = self:RootOf(full)
    if not root or root == full then return true end
    local family = self:GetAltsOf(root)
    Link(full, nil)
    Link(root, full)
    for _, a in ipairs(family) do
        if a ~= full then Link(a, full) end
    end
    return true
end

------------------------------------------------------------------------
-- Officer log (shared with officers only)
------------------------------------------------------------------------
function DB:AddLogEntry(full, text)
    text = ns.Trim(text):gsub("|", "/"):gsub("[\r\n]+", " ")
    if text == "" then return nil end
    text = text:sub(1, ns.Data.MAX_LOG_LENGTH)
    local ts = self:Now()
    local id = ns.Sync.Base36(ts) .. ns.Sync.Base36(math.random(0, 46655))
    local ok, err = ns.Sync:Set("L:" .. full .. ":" .. id, ns.Sync.Codec.Log(ts, ns.ShortName(ns.PlayerFullName()), text))
    if not ok then return nil, err end
    local m = self:GetMember(full)
    return m and m.log and m.log[id]
end

function DB:DeleteLogEntry(full, id)
    local m = self:GetMember(full)
    local entry = m and m.log and m.log[id]
    if not entry or entry.del then return nil end
    local ok = ns.Sync:Set("L:" .. full .. ":" .. id, "")
    return ok and m.log[id] or nil
end

-- Visible entries, newest first.
function DB:GetLog(full)
    local out = {}
    local m = self:GetMember(full)
    if m and m.log then
        for _, e in pairs(m.log) do
            if not e.del then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.id > b.id
    end)
    return out
end

------------------------------------------------------------------------
-- Data reported by the player's own copy of the addon
------------------------------------------------------------------------
function DB:SetSelfReport(snap)
    local me = ns.PlayerFullName()
    if not me then return end
    return ns.Sync:Set("P:" .. me, ns.Sync.Codec.Report(snap))
end
