--[[
    Nootropic Guild Manager - the guild's colors
    From the guild tabard: the background (the cloth), the border (the band)
    and the emblem. Any mix has to read, so text never sits on a raw tabard
    color; it sits on tones made from the guild's own hues:

      accent  the emblem's hue (else the cloth's, else the band's), brightened
              until it reads on a dark window (5:1): headings, labels, tabs
      accent2 its neighbour on the color wheel, the same way
      bar     the cloth's hue (else the band's, else the accent's), darkened
              until light text reads on it (7:1)
      mgr     the band's hue as an accent, when it differs from the accent's
      cloth, band  the tabard itself

    No hue anywhere (white, black, grey) or no tabard: herald blue.
    NGM Peon works out exactly the same (ngm-hub src/accent.ts; the same test
    vectors), so the game and the web always match.

      ns.Accent.Palette(bg, border, emblem) -> { accent, accent2, bar, mgr, cloth, band, herald }
      ns.Accent:Tabard()                    -> bg, border, emblem as hex (or nil)
]]
local _, ns = ...
local A = {}
ns.Accent = A

local PAGE, TEXT = "121110", "f2ecd9"
A.HERALD = { cloth = "2a4f86", band = "12264a" }

local function Rgb(h)
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function Hex(r, g, b)
    local function c(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5 + 1e-6) end -- the same rounding as NGM Peon
    return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end
local function Clamp(x, a, b) return math.max(a, math.min(b, x)) end
-- 0..1 exactly as NGM Peon's ((x % 1) + 1) % 1 (JavaScript's % is C's fmod)
local function Wrap(x) return math.fmod(math.fmod(x, 1) + 1, 1) end

-- HLS as Python's colorsys (hue 0..1)
local function ToHls(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local l = (max + min) / 2
    if max == min then return 0, l, 0 end
    local d = max - min
    local s = l <= 0.5 and d / (max + min) or d / (2 - max - min)
    local rc, gc, bc = (max - r) / d, (max - g) / d, (max - b) / d
    local h
    if r == max then h = bc - gc elseif g == max then h = 2 + rc - bc else h = 4 + gc - rc end
    return Wrap(h / 6), l, s
end
local function FromHls(h, l, s)
    if s == 0 then return l, l, l end
    local m2 = l <= 0.5 and l * (1 + s) or l + s - l * s
    local m1 = 2 * l - m2
    local function v(hue)
        hue = Wrap(hue)
        if hue < 1 / 6 then return m1 + (m2 - m1) * hue * 6 end
        if hue < 0.5 then return m2 end
        if hue < 2 / 3 then return m1 + (m2 - m1) * (2 / 3 - hue) * 6 end
        return m1
    end
    return v(h + 1 / 3), v(h), v(h - 1 / 3)
end

-- WCAG contrast between two hex colors
local function Lum(h)
    local r, g, b = Rgb(h)
    local function c(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b)
end
function A.Contrast(a, b)
    local x, y = Lum(a), Lum(b)
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

local function Valid(x) return type(x) == "string" and x:match("^%x%x%x%x%x%x$") and x:lower() or nil end
-- hue, saturation when the color has a real hue
local function Hued(x)
    x = Valid(x)
    if not x then return nil end
    local h, l, s = ToHls(Rgb(x))
    if s >= 0.15 and l > 0.06 and l < 0.94 then return { h, s } end
    return nil
end
-- brightened (in whole steps, as NGM Peon) until it reads on the window
local function Lift(h, s)
    local c
    for i = 50, 90 do
        c = Hex(FromHls(h, i / 100, s))
        if A.Contrast(c, PAGE) >= 5 then break end
    end
    return c
end
-- darkened until light text reads on it
local function Sink(h, s)
    local c
    for i = 34, 5, -1 do
        c = Hex(FromHls(h, i / 100, s))
        if A.Contrast(TEXT, c) >= 7 then break end
    end
    return c
end
local function Far(x, y) return math.abs(math.fmod(x - y + 1.5, 1) - 0.5) > 0.05 end

function A.Palette(bg, border, emblem)
    local hBg, hBorder, hEmblem = Hued(bg), Hued(border), Hued(emblem)
    local src = hEmblem or hBg or hBorder
    local a = src or Hued(A.HERALD.cloth)
    local as = Clamp(a[2], 0.45, 0.68)
    local c = hBg or hBorder or a
    local mgr = (hBorder and Far(hBorder[1], a[1])) and Lift(hBorder[1], Clamp(hBorder[2], 0.45, 0.68)) or nil
    return {
        accent = Lift(a[1], as), accent2 = Lift(Wrap(a[1] - 0.035), as), bar = Sink(c[1], Clamp(c[2], 0.35, 0.55)), mgr = mgr,
        cloth = Valid(bg) or A.HERALD.cloth, band = Valid(border) or A.HERALD.band, herald = not src,
    }
end

-- Your guild's tabard colours as hex, or nil (no guild, no tabard yet).
-- Never errors: anything unexpected from the game gives nil (house colours).
function A:Tabard()
    if not (IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) then return nil end
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    if not (ok and type(info) == "table") then return nil end
    -- a colour object (GetRGB) on some clients, a plain { r, g, b } on others
    local function h(c)
        if type(c) ~= "table" then return nil end
        local r, g, b
        if type(c.GetRGB) == "function" then
            local fine, x, y, z = pcall(c.GetRGB, c)
            if fine then r, g, b = x, y, z end
        end
        if not r then r, g, b = c.r, c.g, c.b end
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
        return Hex(r, g, b)
    end
    local bg, border, emblem = h(info.backgroundColor), h(info.borderColor), h(info.emblemColor)
    if not (bg and border) then return nil end
    return bg, border, emblem
end

-- /ngm diag: what the game says about the tabard, for troubleshooting.
function A:Diagnose()
    local api = C_GuildInfo and C_GuildInfo.GetGuildTabardInfo
    local line = ("Guild theme: tabard info %s"):format(api and "available" or "|cffff2020not given by this client|r")
    if api then
        local ok, info = pcall(api, "player")
        if not ok then
            line = line .. ", |cffff2020error|r: " .. tostring(info)
        elseif type(info) ~= "table" then
            line = line .. ", returned " .. tostring(info)
        else
            local function describe(c)
                if type(c) ~= "table" then return tostring(c) end
                return (type(c.GetRGB) == "function" and "object" or "table") .. (c.r and (" r=%.2f"):format(c.r) or "")
            end
            line = line .. (", background %s, border %s, emblem %s"):format(describe(info.backgroundColor), describe(info.borderColor), describe(info.emblemColor))
        end
    end
    local bg, border, emblem = self:Tabard()
    local p = A.Palette(bg, border, emblem)
    ns:Print(line .. (". Read as %s/%s/%s, accent %s, bar %s%s."):format(tostring(bg), tostring(border), tostring(emblem), p.accent, p.bar, p.herald and " (herald blue)" or ""))
end
