--[[
    Nootropic Guild Manager - Custom recruitment messages
    Rules pick the whisper each player gets. Rules are checked top to bottom
    (their order is their priority); the first enabled rule whose filters all
    match the player decides the message. Players no rule matches get the
    Default message. Empty filters match everyone.

    Saved per guild in guild.recruit:
      useRules = true/false
      rules = { {
          id, name, enabled,
          classes = { [CLASSFILE] = true },          -- empty = any class
          races   = { ["night elf"] = true },        -- lowercase; empty = any race
          minLevel, maxLevel,                         -- nil = no limit
          zones   = "Elwynn, Westfall",               -- any part of the zone name; empty = anywhere
          guild   = "any" | "none" | "guilded",
          text    = "message with $name, $class ...",
          preset  = CLASSFILE,                       -- one of the built-in class messages
      }, ... }
      classDefaults = true                    -- built-in class messages were added once

    Messages can be exported to plain text and imported back (see Export).
]]
local _, ns = ...
local D = ns.Data
local MS = {}
ns.Messages = MS

MS.RACES = { "Human", "Dwarf", "Night Elf", "Gnome", "Orc", "Undead", "Tauren", "Troll" }
MS.FACTION_RACES = {
    Alliance = { "Human", "Dwarf", "Night Elf", "Gnome" },
    Horde = { "Orc", "Undead", "Tauren", "Troll" },
}
-- Classes only one faction could play in original Classic. WoW: Forever lets
-- both factions play them (Horde Paladins exist), so every class gets a message.
local FACTION_CLASS = {}
local ONCE_FACTION_ONLY = { "PALADIN", "SHAMAN" } -- skipped by 1.12 and older

-- Built-in message for each class.
MS.CLASS_DEFAULTS = {
    WARRIOR = "Hi $name! $guild could use a sturdy Warrior like you for dungeons and raids. We're friendly and help each other level. Want an invite? Just reply \"invite\".",
    PALADIN = "Hi $name! $guild would love a Paladin along - healing, tanking or Retribution, all welcome. Friendly guild with regular dungeon runs. Reply \"invite\" if you'd like to join.",
    HUNTER = "Hi $name! $guild is a friendly guild that quests, runs dungeons and raids together, and we'd love a Hunter (and pet) along. Want an invite? Just reply \"invite\".",
    ROGUE = "Hi $name! $guild is looking for a Rogue to run dungeons and raids with. Friendly folks, no pressure. Reply \"invite\" if you want in.",
    PRIEST = "Hi $name! Every group needs a good Priest, and $guild would love to have you. Friendly guild, regular dungeons and raids. Reply \"invite\" if you'd like to join.",
    SHAMAN = "Hi $name! $guild would love a Shaman for dungeons and raids - totems always welcome. Friendly guild that helps each other level. Reply \"invite\" if you'd like to join.",
    MAGE = "Hi $name! $guild could use a Mage for dungeons and raids (and the odd portal). Friendly, helpful guild. Want an invite? Just reply \"invite\".",
    WARLOCK = "Hi $name! $guild is looking for a Warlock for dungeons and raids (summons appreciated!). Friendly, helpful guild. Reply \"invite\" if you'd like to join.",
    DRUID = "Hi $name! $guild would love a Druid - tank, healer or damage, we can use it all. Friendly guild with regular dungeon runs. Reply \"invite\" if you'd like to join.",
}

local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Alliance" or f == "Horde") and f or nil
end

-- Races shown in the editor: your faction's (all eight if it isn't known).
function MS:FactionRaces()
    return self.FACTION_RACES[Faction() or ""] or self.RACES
end

-- Classes your faction can play (every class in WoW: Forever).
function MS:FactionClasses()
    local out, mine = {}, Faction()
    for _, cls in ipairs(D.CLASSES) do
        if not (mine and FACTION_CLASS[cls] and FACTION_CLASS[cls] ~= mine) then out[#out + 1] = cls end
    end
    return out
end

local function Settings() return ns.Recruit:Settings() end
local function Changed() ns:Fire("MESSAGES_CHANGED") end

-- 1.08 had one message per class: turn those into rules once.
function MS:Migrate(r)
    if r.rules then
        -- 1.10: gender filters removed (the game doesn't tell us a player's gender)
        for _, rule in ipairs(r.rules) do rule.sex = nil end
        if not r.classDefaults then
            local hadRules = #r.rules > 0
            self:AddClassDefaults(r, true)
            if not hadRules then r.useRules = true end
        elseif not r.classDefaultsAllFactions then
            -- 1.13: Paladin (Horde) and Shaman (Alliance) were left out before
            self:AddClassDefaults(r, true, ONCE_FACTION_ONLY)
        end
        r.classDefaultsAllFactions = true
        return
    end
    r.rules = {}
    r.nextRuleId = r.nextRuleId or 1
    for _, cls in ipairs(D.CLASSES) do
        local text = r.templates and r.templates[cls]
        if text and ns.Trim(text) ~= "" then
            local rule = self:Blank(r)
            rule.name = D:ClassName(cls)
            rule.classes[cls] = true
            rule.text = text
            rule.preset = cls
            r.rules[#r.rules + 1] = rule
        end
    end
    r.templates = nil
    self:AddClassDefaults(r, true)
    r.classDefaultsAllFactions = true
    if r.useRules == nil then r.useRules = true end
end

-- Adds the built-in message (turned on) for every class that doesn't have
-- one in the list, or only for the classes in `only`. Returns how many were added.
function MS:AddClassDefaults(r, silent, only)
    r = r or Settings()
    if not r then return 0 end
    local have = {}
    for _, rule in ipairs(r.rules) do
        if rule.preset then have[rule.preset] = true end
        -- a message of your own for just one class counts too
        local only, n = nil, 0
        for cls in pairs(rule.classes or {}) do only, n = cls, n + 1 end
        if n == 1 and not next(rule.races or {}) and ns.Trim(rule.zones or "") == "" and (rule.guild or "any") == "any"
            and (rule.minLevel or 1) <= 1 and (rule.maxLevel or 999) >= ns.Recruit:MaxLevel() then
            have[only] = true
        end
    end
    local wanted
    if only then
        wanted = {}
        for _, cls in ipairs(only) do wanted[cls] = true end
    end
    local added = 0
    for _, cls in ipairs(self:FactionClasses()) do
        if not have[cls] and (not wanted or wanted[cls]) then
            local rule = self:Blank(r)
            rule.name = D:ClassName(cls)
            rule.classes[cls] = true
            rule.text = self.CLASS_DEFAULTS[cls]
            rule.preset = cls
            r.rules[#r.rules + 1] = rule
            added = added + 1
        end
    end
    r.classDefaults = true
    if added > 0 and not silent then Changed() end
    return added
end

function MS:Blank(r)
    r = r or Settings()
    local id = r.nextRuleId or 1
    r.nextRuleId = id + 1
    return {
        id = id, name = "New message", enabled = true,
        classes = {}, races = {}, guild = "any", zones = "", text = "",
        minLevel = 1, maxLevel = ns.Recruit:MaxLevel(),
    }
end

function MS:Rules()
    local r = Settings()
    return r and r.rules or {}
end

function MS:Get(id)
    for i, rule in ipairs(self:Rules()) do
        if rule.id == id then return rule, i end
    end
end


function MS:New()
    local r = Settings()
    if not r then return end
    local rule = self:Blank(r)
    table.insert(r.rules, rule)
    Changed()
    return rule
end

function MS:Duplicate(id)
    local r = Settings()
    local src, i = self:Get(id)
    if not (r and src) then return end
    local copy = self:Blank(r)
    for k, v in pairs(src) do
        if k ~= "id" then
            if type(v) == "table" then
                copy[k] = {}
                for kk, vv in pairs(v) do copy[k][kk] = vv end
            else
                copy[k] = v
            end
        end
    end
    copy.name = src.name .. " (copy)"
    table.insert(r.rules, i + 1, copy)
    Changed()
    return copy
end

function MS:Delete(id)
    local r = Settings()
    local _, i = self:Get(id)
    if r and i then
        table.remove(r.rules, i)
        Changed()
    end
end

-- Moves a rule up (-1) or down (+1) in priority.
function MS:Move(id, delta)
    local r = Settings()
    local _, i = self:Get(id)
    if not (r and i) then return end
    local j = i + delta
    if j < 1 or j > #r.rules then return end
    r.rules[i], r.rules[j] = r.rules[j], r.rules[i]
    Changed()
end

function MS:Update(id, field, value)
    local rule = self:Get(id)
    if not rule then return end
    rule[field] = value
    Changed()
end

function MS:SetUseRules(on)
    local r = Settings()
    if r then
        r.useRules = on and true or false
        Changed()
    end
end

------------------------------------------------------------------------
-- Matching
------------------------------------------------------------------------
-- Every filter must match; an empty filter matches anyone.
function MS:Matches(rule, p)
    if not rule.enabled or ns.Trim(rule.text or "") == "" then return false end
    if next(rule.classes) and not rule.classes[p.classFile or ""] then return false end
    if next(rule.races) and not rule.races[(p.race or ""):lower()] then return false end
    local lvl = tonumber(p.level) or 0
    if rule.minLevel and lvl < rule.minLevel then return false end
    if rule.maxLevel and lvl > rule.maxLevel then return false end
    local zones = ns.Trim(rule.zones or "")
    if zones ~= "" then
        local zone, hit = (p.zone or ""):lower(), false
        for part in zones:gmatch("[^,]+") do
            part = ns.Trim(part):lower()
            if part ~= "" and zone:find(part, 1, true) then hit = true break end
        end
        if not hit then return false end
    end
    if rule.guild == "none" and p.guild then return false end
    if rule.guild == "guilded" and not p.guild then return false end
    return true
end

-- The message for a player: text, rule (nil = Default message).
function MS:Pick(p)
    local r = Settings()
    if not r then return "", nil end
    if r.useRules then
        for _, rule in ipairs(r.rules) do
            if self:Matches(rule, p) then return rule.text, rule end
        end
    end
    return r.default or "", nil
end

-- Short description of a rule's filters, e.g. "Mage, Priest - Night Elf - 10-29".
function MS:Summary(rule)
    local parts = {}
    local cls = {}
    for _, c in ipairs(D.CLASSES) do if rule.classes[c] then cls[#cls + 1] = D:ClassName(c) end end
    if #cls > 0 then parts[#parts + 1] = table.concat(cls, ", ") end
    local races = {}
    for _, race in ipairs(self.RACES) do if rule.races[race:lower()] then races[#races + 1] = race end end
    if #races > 0 then parts[#parts + 1] = table.concat(races, ", ") end
    local maxL = ns.Recruit:MaxLevel()
    if (rule.minLevel and rule.minLevel > 1) or (rule.maxLevel and rule.maxLevel < maxL) then
        parts[#parts + 1] = ("Lvl %s-%s"):format(rule.minLevel or 1, rule.maxLevel or ns.Recruit:MaxLevel())
    end
    if ns.Trim(rule.zones or "") ~= "" then parts[#parts + 1] = ns.Trim(rule.zones) end
    if rule.guild == "none" then parts[#parts + 1] = "No guild" elseif rule.guild == "guilded" then parts[#parts + 1] = "In a guild" end
    if #parts == 0 then return "Everyone" end
    return table.concat(parts, " - ")
end

------------------------------------------------------------------------
-- Import / export (plain text)
--
--   message: Night Elf Druids
--   on: yes
--   classes: Druid
--   races: Night Elf
--   levels: 10-60
--   zones: Teldrassil, Darkshore
--   guild: any            (any, none, guilded)
--   text: Hi $name! ...
--
-- Blocks start with "message:". Missing lines mean "any". Lines starting
-- with # are ignored.
------------------------------------------------------------------------
local GUILD_WORDS = { any = "any", none = "none", ["no guild"] = "none", unguilded = "none",
    guilded = "guilded", ["in a guild"] = "guilded", guild = "guilded" }

function MS:Export(rules)
    rules = rules or self:Rules()
    local out = {
        "# Nootropic Guild Manager custom messages",
        "# Copy this text to share it. Import adds the messages back in this order.",
    }
    local maxL = ns.Recruit:MaxLevel()
    for _, rule in ipairs(rules) do
        out[#out + 1] = ""
        out[#out + 1] = "message: " .. (rule.name or "")
        out[#out + 1] = "on: " .. (rule.enabled and "yes" or "no")
        local cls = {}
        for _, c in ipairs(D.CLASSES) do if rule.classes[c] then cls[#cls + 1] = D:ClassName(c) end end
        out[#out + 1] = "classes: " .. (#cls > 0 and table.concat(cls, ", ") or "any")
        local races = {}
        for _, race in ipairs(self.RACES) do if rule.races[race:lower()] then races[#races + 1] = race end end
        out[#out + 1] = "races: " .. (#races > 0 and table.concat(races, ", ") or "any")
        out[#out + 1] = ("levels: %d-%d"):format(rule.minLevel or 1, rule.maxLevel or maxL)
        out[#out + 1] = "zones: " .. (ns.Trim(rule.zones or "") ~= "" and ns.Trim(rule.zones) or "any")
        out[#out + 1] = "guild: " .. (rule.guild or "any")
        out[#out + 1] = "text: " .. (rule.text or ""):gsub("[\r\n]+", " ")
    end
    return table.concat(out, "\n")
end

local function ClassFromName(name)
    name = ns.Trim(name):lower()
    for _, c in ipairs(D.CLASSES) do
        if c:lower() == name or D:ClassName(c):lower() == name then return c end
    end
end

local function RaceFromName(name)
    name = ns.Trim(name):lower():gsub("%s+", " ")
    if name == "nightelf" then name = "night elf" end
    if name == "scourge" then name = "undead" end
    for _, race in ipairs(MS.RACES) do
        if race:lower() == name then return race:lower() end
    end
end

local function IsAny(v) v = ns.Trim(v or ""):lower() return v == "" or v == "any" or v == "all" end

-- Reads exported text. Returns rules (not yet added) and a list of problems.
function MS:Parse(text)
    local rules, problems = {}, {}
    local cur
    local function finish()
        if not cur then return end
        if ns.Trim(cur.text) == "" then
            problems[#problems + 1] = ("\"%s\" has no text and was skipped."):format(cur.name)
        else
            rules[#rules + 1] = cur
        end
        cur = nil
    end
    local n = 0
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        line = ns.Trim(line:gsub("\r", ""))
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([%a ]-)%s*:%s*(.*)$")
            key = key and key:lower()
            if key == "message" or key == "name" then
                finish()
                cur = { name = value ~= "" and value:sub(1, 40) or "Imported message", enabled = true,
                    classes = {}, races = {}, guild = "any", zones = "", text = "" }
            elseif not cur then
                problems[#problems + 1] = ("Line %d is outside a message (start each one with \"message:\")."):format(n)
            elseif key == "on" or key == "enabled" then
                local v = value:lower()
                cur.enabled = not (v == "no" or v == "off" or v == "false" or v == "0")
            elseif key == "classes" or key == "class" then
                if not IsAny(value) then
                    for part in value:gmatch("[^,]+") do
                        local c = ClassFromName(part)
                        if c then cur.classes[c] = true
                        else problems[#problems + 1] = ("Unknown class \"%s\" in \"%s\"."):format(ns.Trim(part), cur.name) end
                    end
                end
            elseif key == "races" or key == "race" then
                if not IsAny(value) then
                    for part in value:gmatch("[^,]+") do
                        local race = RaceFromName(part)
                        if race then cur.races[race] = true
                        else problems[#problems + 1] = ("Unknown race \"%s\" in \"%s\"."):format(ns.Trim(part), cur.name) end
                    end
                end
            elseif key == "levels" or key == "level" then
                local lo, hi = value:match("^(%d*)%s*%-%s*(%d*)$")
                if not lo then lo = value:match("^(%d+)$") hi = lo end
                cur.minLevel, cur.maxLevel = tonumber(lo), tonumber(hi)
            elseif key == "zones" or key == "zone" then
                cur.zones = IsAny(value) and "" or value:sub(1, 120)
            elseif key == "guild" then
                cur.guild = GUILD_WORDS[value:lower()] or "any"
            elseif key == "text" or key == "message text" then
                cur.text = value:sub(1, D.WHISPER_MAX)
            else
                problems[#problems + 1] = ("Line %d wasn't understood: %s"):format(n, line:sub(1, 40))
            end
        end
    end
    finish()
    return rules, problems
end

-- mode: "add" (after your messages) or "replace". Returns count, problems.
function MS:Import(text, mode)
    local r = Settings()
    if not r then return 0, { "Join a guild first." } end
    local parsed, problems = self:Parse(text)
    if #parsed == 0 then
        if #problems == 0 then problems[1] = "No messages found. Each one starts with \"message:\"." end
        return 0, problems
    end
    if mode == "replace" then wipe(r.rules) end
    local maxL = ns.Recruit:MaxLevel()
    for _, p in ipairs(parsed) do
        local rule = self:Blank(r)
        for k, v in pairs(p) do rule[k] = v end
        rule.minLevel = rule.minLevel or 1
        rule.maxLevel = rule.maxLevel or maxL
        -- an imported copy of a built-in class message counts as that preset
        for cls, text in pairs(self.CLASS_DEFAULTS) do
            if rule.text == text and rule.classes[cls] then rule.preset = cls end
        end
        r.rules[#r.rules + 1] = rule
    end
    Changed()
    return #parsed, problems
end
