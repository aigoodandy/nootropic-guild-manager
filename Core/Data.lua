--[[
    Nootropic Guild Manager - Static data
    Classes, specializations, professions, tag palette and defaults.
]]
local _, ns = ...
local D = {}
ns.Data = D

------------------------------------------------------------------------
-- Specializations (talent trees) per class
------------------------------------------------------------------------
D.CLASS_SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat", "Subtlety" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MAGE    = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID   = { "Balance", "Feral Combat", "Restoration" },
}

local ICON = "Interface\\Icons\\"

D.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
function D:ClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or CLASS_NAMES[classFile] or classFile
end

-- Talent tree icons, as shown on each class's talent tabs.
D.SPEC_ICONS = {
    WARRIOR = { ["Arms"] = "Ability_Rogue_Eviscerate", ["Fury"] = "Ability_Warrior_InnerRage", ["Protection"] = "INV_Shield_06" },
    PALADIN = { ["Holy"] = "Spell_Holy_HolyBolt", ["Protection"] = "Spell_Holy_DevotionAura", ["Retribution"] = "Spell_Holy_AuraOfLight" },
    HUNTER  = { ["Beast Mastery"] = "Ability_Hunter_BeastTaming", ["Marksmanship"] = "Ability_Marksmanship", ["Survival"] = "Ability_Hunter_SwiftStrike" },
    ROGUE   = { ["Assassination"] = "Ability_Rogue_Eviscerate", ["Combat"] = "Ability_BackStab", ["Subtlety"] = "Ability_Stealth" },
    PRIEST  = { ["Discipline"] = "Spell_Holy_WordFortitude", ["Holy"] = "Spell_Holy_GuardianSpirit", ["Shadow"] = "Spell_Shadow_ShadowWordPain" },
    SHAMAN  = { ["Elemental"] = "Spell_Nature_Lightning", ["Enhancement"] = "Spell_Nature_LightningShield", ["Restoration"] = "Spell_Nature_MagicImmunity" },
    MAGE    = { ["Arcane"] = "Spell_Holy_MagicalSentry", ["Fire"] = "Spell_Fire_FireBolt02", ["Frost"] = "Spell_Frost_FrostBolt02" },
    WARLOCK = { ["Affliction"] = "Spell_Shadow_DeathCoil", ["Demonology"] = "Spell_Shadow_Metamorphosis", ["Destruction"] = "Spell_Shadow_RainOfFire" },
    DRUID   = { ["Balance"] = "Spell_Nature_StarFall", ["Feral Combat"] = "Ability_Racial_BearForm", ["Restoration"] = "Spell_Nature_HealingTouch",
                ["Feral"] = "Ability_Racial_BearForm", ["Guardian"] = "Ability_Racial_BearForm" },
}
local specLookup = {}
for classFile, specs in pairs(D.SPEC_ICONS) do
    specLookup[classFile] = {}
    for name, icon in pairs(specs) do specLookup[classFile][name:lower()] = ICON .. icon end
end

-- Icon for a class's spec (case-insensitive), or nil when unknown.
function D:SpecIcon(classFile, spec)
    local t = classFile and specLookup[classFile]
    return t and spec and t[spec:lower()]
end

------------------------------------------------------------------------
-- Addon icon choices (window portrait, minimap button, shortcuts)
------------------------------------------------------------------------
D.ICON_STYLES = {
    { key = "mug",    label = "Ale Mug",        icon = ICON .. "INV_Drink_13" },
    { key = "stein",  label = "Brewfest Stein", icon = ICON .. "INV_Holiday_BrewfestBuff_01" },
    { key = "emblem", label = "Guild Emblem",   icon = ICON .. "INV_Drink_13" }, -- icon = fallback outside a guild
}
D.DEFAULT_ICON = ICON .. "INV_Drink_13"

function D:IconStyle(key)
    for _, s in ipairs(self.ICON_STYLES) do
        if s.key == key then return s end
    end
    return self.ICON_STYLES[1]
end

------------------------------------------------------------------------
-- Minimap button click actions (Options > Minimap Button)
------------------------------------------------------------------------
D.MINIMAP_ACTIONS = {
    { key = "roster",  label = "Open Roster" },
    { key = "recruit", label = "Open Recruitment" },
    { key = "polls",   label = "Open Polls" },
    { key = "tags",    label = "Open Tags (officers)" },
    { key = "audit",   label = "Open Audit (officers)" },
    { key = "reviews", label = "Open Reviews" },
    { key = "options", label = "Open Options" },
    { key = "toggle",  label = "Show / hide window" },
    { key = "none",    label = "Do nothing" },
}
function D:MinimapActionLabel(key)
    for _, a in ipairs(self.MINIMAP_ACTIONS) do
        if a.key == key then return a.label end
    end
    return "Do nothing"
end

------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------
D.PROFESSIONS = {
    { name = "Alchemy",        icon = ICON .. "Trade_Alchemy" },
    { name = "Blacksmithing",  icon = ICON .. "Trade_BlackSmithing" },
    { name = "Enchanting",     icon = ICON .. "Trade_Engraving" },
    { name = "Engineering",    icon = ICON .. "Trade_Engineering" },
    { name = "Herbalism",      icon = ICON .. "Trade_Herbalism" },
    { name = "Leatherworking", icon = ICON .. "INV_Misc_ArmorKit_17" },
    { name = "Mining",         icon = ICON .. "Trade_Mining" },
    { name = "Skinning",       icon = ICON .. "INV_Misc_Pelt_Wolf_01" },
    { name = "Tailoring",      icon = ICON .. "Trade_Tailoring" },
    { name = "Cooking",        icon = ICON .. "INV_Misc_Food_15",           secondary = true },
    { name = "First Aid",      icon = ICON .. "Spell_Holy_SealOfSacrifice", secondary = true },
    { name = "Fishing",        icon = ICON .. "Trade_Fishing",              secondary = true },
}
D.PROF_MAX_RANK = 300
D.UNKNOWN_ICON = ICON .. "INV_Misc_QuestionMark"

local byName = {}
for _, p in ipairs(D.PROFESSIONS) do byName[p.name:lower()] = p end

function D:GetProfession(name)
    return name and byName[name:lower()]
end

function D:IsPrimary(name)
    local p = self:GetProfession(name)
    return not (p and p.secondary)
end

function D:ProfIcon(prof)
    if prof.icon then return prof.icon end
    local p = self:GetProfession(prof.name)
    return p and p.icon or D.UNKNOWN_ICON
end

------------------------------------------------------------------------
-- Content tags
------------------------------------------------------------------------
D.TAG_COLORS = {
    { name = "Gold",    1.00, 0.82, 0.00 },
    { name = "Azure",   0.25, 0.60, 1.00 },
    { name = "Violet",  0.64, 0.35, 1.00 },
    { name = "Crimson", 0.92, 0.22, 0.22 },
    { name = "Ember",   1.00, 0.50, 0.10 },
    { name = "Jade",    0.20, 0.80, 0.55 },
    { name = "Moss",    0.50, 0.78, 0.20 },
    { name = "Frost",   0.40, 0.85, 0.95 },
    { name = "Rose",    1.00, 0.45, 0.70 },
    { name = "Silver",  0.72, 0.72, 0.72 },
}

function D:TagColor(index)
    local c = self.TAG_COLORS[index or 1] or self.TAG_COLORS[1]
    return c[1], c[2], c[3]
end

-- "|cffrrggbb" for a tag color
function D:TagColorHex(index)
    local r, g, b = self:TagColor(index)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- { name, colorIndex, icon }
D.DEFAULT_TAGS = {
    { "Questing",      1,  ICON .. "INV_Scroll_03" },
    { "Dungeons",      2,  ICON .. "INV_Sword_04" },
    { "Raiding",       3,  ICON .. "INV_Misc_Head_Dragon_01" },
    { "World PvP",     4,  ICON .. "Ability_DualWield" },
    { "Battlegrounds", 5,  ICON .. "INV_BannerPVP_02" },
    { "Crafting",      6,  ICON .. "Trade_BlackSmithing" },
    { "Gathering",     7,  ICON .. "Trade_Herbalism" },
    { "Leveling",      8,  ICON .. "Ability_Mount_RidingHorse" },
    { "Roleplay",      9,  ICON .. "Spell_Shadow_Charm" },
    { "Social",        10, ICON .. "INV_Drink_05" },
}

-- Default kudos: { name, colorIndex, icon }. Officers can rename, recolor,
-- re-icon or retire them, and add their own (up to D.MAX_KUDOS active).
D.DEFAULT_KUDOS = {
    { "Great Tank",    2, "INV_Shield_06" },
    { "Healer Hero",   6, "Spell_Nature_HealingTouch" },
    { "Damage Dealer", 4, "INV_Sword_04" },
    { "Group Leader",  5, "INV_BannerPVP_02" },
    { "Helpful",       1, "Spell_Holy_SealOfSacrifice" },
    { "Good Teacher",  3, "INV_Misc_Book_09" },
    { "Generous",      7, "INV_Misc_Coin_02" },
    { "Good Vibes",    8, "INV_Drink_05" },
    { "Funny",         9, "INV_Misc_Head_Murloc_01" },
}
D.MAX_KUDOS = 12

-- Tag icons are stored as a file id ("134400") or a texture path.
function D:ParseIcon(v)
    if not v or v == "" then return nil end
    local id = tonumber(v)
    if id then return id end
    if not v:find("\\", 1, true) then return ICON .. v end
    return v
end

-- The icon to draw for a tag: its chosen icon, a default tag's own icon, or a question mark.
function D:TagIcon(tag)
    if tag.icon then return tag.icon end
    local i = tag.id and tonumber(tag.id:match("^d(%d+)$"))
    local def = i and self.DEFAULT_TAGS[i]
    return def and def[3] or self.UNKNOWN_ICON
end

-- "|T...|t" for a tag icon in text (menus, tooltips).
function D:TagIconString(tag, size)
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(self:TagIcon(tag)), size or 14, size or 14)
end

-- Icon and colored name, for tooltips and menus.
function D:TagLabel(tag, size)
    return self:TagIconString(tag, size) .. " " .. self:TagColorHex(tag.color) .. tag.name .. "|r"
end
D.MAX_TAG_LENGTH = 24
D.MAX_LOG_LENGTH = 140 -- fits one addon message

------------------------------------------------------------------------
-- Recruitment defaults
------------------------------------------------------------------------
D.DEFAULT_WHISPER = "Hi $name! $guild is looking for friendly players to quest, run dungeons and raid with. Want an invite? Just reply \"invite\"."
D.DEFAULT_KEYWORDS = { "invite", "inv", "yes", "sure", "interested" }
D.MAX_KEYWORDS = 5
-- Replies that put someone on the Do Not Whisper list (whole words, any case)
D.DEFAULT_DNW_WORDS = { "dnw", "leave me alone", "do not whisper", "stop whispering", "not interested" }
D.WHISPER_MAX = 255

------------------------------------------------------------------------
-- Rating (how well they play their class)
------------------------------------------------------------------------
-- Star icons for a rating: |T|t textures render in any font.
D.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
function D:StarText(n, size)
    n = tonumber(n) or 0
    if n <= 0 then return "|cff9d9d9dnone|r" end
    return string.rep(("|T%s:%d|t"):format(self.STAR, size or 12), n)
end

D.RATING_LABELS = { -- no longer shown; kept for older saved references
    [0] = "Unrated",
    [1] = "Needs work",
    [2] = "Learning",
    [3] = "Capable",
    [4] = "Strong",
    [5] = "Exceptional",
}
