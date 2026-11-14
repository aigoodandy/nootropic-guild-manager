--[[
    Nootropic Guild Manager - What you share
    A switch only for what comes from your own copy of the addon and nowhere
    else, so you can keep it to yourself:

      recipes   the recipes you've learned (RP records, Who Can Craft?)
      ("Learn when I usually play" lives in Services/Profile.lua, per character)

    Everything else is shared always: it's public anyway (Blizzard's API and
    armory, the guild roster, inspecting you in game, guild chat):

      report    your spec and professions as the game reports them (P record)
      stats     your character statistics and guild chat time (HF record)
      together  appearing in guildmates' Play Together lists (online, level)

    Turning recipes off clears what was already shared: the records are
    emptied, so guildmates' copies drop them too.
]]
local _, ns = ...
local SH = {}
ns.Sharing = SH

-- the switches; anything else is always on
SH.KEYS = { recipes = "shareRecipes" }

local function Me() return ns.PlayerFullName() end

function SH:Get(key)
    local k = self.KEYS[key]
    if not k then return true end
    return ns.DB:Settings()[k] ~= false
end

function SH:Set(key, on)
    local k = self.KEYS[key]
    if not k then return end
    ns.DB:Settings()[k] = on and true or false
    self:Enforce(key)
    ns:Fire("SETTINGS_CHANGED")
end

-- Makes what's shared match (one key, or all of them).
function SH:Enforce(only)
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    local me = Me()
    if not only or only == "report" then ns.Comm:Report() end
    if (not only or only == "recipes") and not self:Get("recipes") then
        local prefix = "RP:" .. me .. ":"
        for key, rec in pairs(ns.Sync:Store("guild") or {}) do
            if key:sub(1, #prefix) == prefix and rec.v ~= "" then ns.Sync:Set(key, "") end
        end
    end
    if not only or only == "stats" then ns.HallOfFame:Publish() end
    -- Play Together: no hiding any more (online and level are on the roster);
    -- clear an old "left out" mark
    if not only or only == "together" then
        if (ns.Sync:Value("PS:" .. me) or "") ~= "" then ns.Sync:Set("PS:" .. me, "") end
    end
end

function SH:Init()
    -- once the guild's data has loaded
    C_Timer.After(20, ns.Safe(function() SH:Enforce() end, "Sharing"))
end
