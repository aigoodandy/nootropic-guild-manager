--[[
    Nootropic Guild Manager - Text size
    The addon draws its text with its own copies of the game's fonts
    ("NootropicGM_GameFontNormal" and so on), so Options > Text Size can make
    the addon's text bigger or smaller without touching the rest of the UI.
    Changing a font object updates every text using it right away.

    Saved in settings.fontDelta: points added to each font's normal size.
]]
local _, ns = ...
local F = {}
ns.Fonts = F

F.MIN, F.MAX = -2, 6
F.NAMES = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge",
    "GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge",
    "NumberFontNormalSmall",
}
F.objects = {} -- Blizzard name -> our font object
local base = {} -- Blizzard name -> its size when we loaded

for _, name in ipairs(F.NAMES) do
    local src = _G[name] or GameFontNormal
    local obj = CreateFont("NootropicGM_" .. name)
    obj:CopyFontObject(src)
    F.objects[name] = obj
    local _, size = src:GetFont()
    base[name] = size or 12
end

function F:Delta()
    local d = ns.DB.sv and ns.DB:Settings().fontDelta or 0
    return math.max(self.MIN, math.min(self.MAX, tonumber(d) or 0))
end

-- Resizes every addon font to its normal size plus the chosen difference.
function F:Apply()
    local delta = self:Delta()
    for name, obj in pairs(self.objects) do
        local src = _G[name] or GameFontNormal
        local path, _, flags = src:GetFont()
        if path then obj:SetFont(path, math.max(6, base[name] + delta), flags or "") end
    end
end

function F:Set(delta)
    ns.DB:Settings().fontDelta = math.max(self.MIN, math.min(self.MAX, delta))
    self:Apply()
    ns:Fire("FONTS_CHANGED")
end

-- "Normal", "+2", "-1"
function F:Label()
    local d = self:Delta()
    if d == 0 then return "Normal" end
    return (d > 0 and "+" or "") .. d
end
