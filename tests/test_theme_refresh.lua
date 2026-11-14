-- The guild's colors at login: this character's last ones before the game
-- says which guild you're in, and always the tabard's once it does (even when
-- they match what's saved: the bug that left some windows herald blue).
local ROOT = arg[1] or ".."
local ns = {}
function CreateFont(name) return { SetFontObject = function() end, SetTextColor = function(self, r, g, b) self.rgb = { r, g, b } end } end
UnitName = function() return "Marc" end
GetRealmName = function() return "Forever" end
local inGuild, tabard = false, nil
IsInGuild = function() return inGuild end
assert(loadfile(ROOT .. "/Core/Accent.lua"))("NootropicGuildManager", ns)
ns.Accent.Tabard = function() if tabard then return tabard[1], tabard[2], tabard[3] end end
assert(loadfile(ROOT .. "/UI/Theme.lua"))("NootropicGuildManager", ns)
local T = ns.Theme
local guilds = {}
ns.DB = { sv = {}, Guild = function() return inGuild and guilds.g or nil end }
local blue, noot = ns.Accent.Palette(nil, nil).accent, ns.Accent.Palette("232323", "6d0077", "376700").accent

-- first login ever, guild not known yet: herald blue
T:LoadTheme()
assert(T.HEX.yellow == blue, "first login: herald blue")
-- the tabard arrives: Nootropic's colors, remembered for this character
inGuild, tabard = true, { "232323", "6d0077", "376700" }
guilds.g = {}
T:RefreshAccent()
assert(T.HEX.yellow == noot and T.palette.cloth == "232323", "tabard known: the guild's colors")
assert(ns.DB.sv.charThemes["Marc-Forever"].border == "6d0077", "remembered per character")

-- next login: the game doesn't know the guild yet, but the colors are right at once
inGuild, tabard = false, nil
T:ApplyPalette(nil) -- (a fresh session)
T:LoadTheme()
assert(T.HEX.yellow == noot, "next login: the guild's colors before the guild is known")
-- the tabard, unchanged from what's saved, still gets applied (not skipped)
T:ApplyPalette(ns.Accent.Palette(nil, nil))
inGuild, tabard = true, { "232323", "6d0077", "376700" }
T:RefreshAccent()
assert(T.HEX.yellow == noot, "an unchanged tabard is still shown")

-- left the guild: herald blue, and forgotten for this character
inGuild, tabard = false, nil
T:RefreshAccent()
assert(T.HEX.yellow == blue and ns.DB.sv.charThemes["Marc-Forever"] == nil, "no guild: herald blue")
print("OK")
