--[[
    Nootropic Guild Manager - Theme (3.0)
    The addon looks like the game's own windows: Blizzard's frames, buttons,
    tick boxes and scroll bars, and the game's own fonts (so every alphabet
    shows, and nothing extra is shipped). The theme only colors the accents:
    headings, labels, highlighted words, the open tab and the bars, always in
    the guild tabard's colors (Core/Accent.lua), exactly as NGM Peon's
    dashboard and Discord posts; herald blue without a tabard.

    ns.Theme.C.yellow          {r, g, b}: the accent (gold, or the guild's)
    ns.Theme.HEX.yellow        "ffd100" (for |cff...|r)
    ns.Theme:Skin(frame)       a window: the game's own look, the accent kept fresh
    ns.Theme:SkinButton(b)     a button: the game's own
    ns.Theme:Box(frame)        a panel, as the game's tooltips
    ns.Theme:Dashes(host)      a thin divider
    ns.Theme:Paint/Tint/Ink/Fill/EdgeColor(obj, color, a)
                               draw in a theme colour (repainted when it changes)
    ns.Theme:Toast(title, text)  a short banner at the top of the screen
]]
local _, ns = ...
local T = {}
ns.Theme = T

-- Blizzard's own colours (FrameXML's NORMAL_FONT_COLOR, HIGHLIGHT, GRAY...)
T.HEX = {
    yellow = "ffd100", orange = "ff8000", red = "ff2020", green = "20ff20", blue = "71d5ff",
    aqua = "40c0ff", purple = "a335ee",
    fg = "ffffff", dim = "9d9d9d", faint = "6e6e6e",
    bg = "000000", bg1 = "0d0c0a", line = "3a352c", edge = "806a3f", shade = "000000",
}
T.C = {}
for k, h in pairs(T.HEX) do
    T.C[k] = { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

-- name -> { the game's font object, colour role (nil: the game's own colour) }
local OBJECTS = {
    NGMFontTitle        = { "GameFontNormal", "yellow" },
    NGMFontHuge         = { "GameFontNormalHuge", "yellow" },
    NGMFontLabel        = { "GameFontNormal", "yellow" },
    NGMFontLabelSmall   = { "GameFontNormalSmall", "yellow" },
    NGMFontText         = { "GameFontHighlight" },
    NGMFontTextSmall    = { "GameFontHighlightSmall" },
    NGMFontDim          = { "GameFontDisable" },
    NGMFontDimSmall     = { "GameFontDisableSmall" },
    NGMFontNumber       = { "NumberFontNormalSmall" },
    NGMFontButton       = { "GameFontNormal" },
    NGMFontButtonSmall  = { "GameFontNormalSmall" },
}

for name, spec in pairs(OBJECTS) do
    if not _G[name] then
        local obj = CreateFont(name)
        if _G[spec[1]] then obj:SetFontObject(_G[spec[1]]) end
        local c = spec[2] and T.C[spec[2]]
        if c then obj:SetTextColor(c[1], c[2], c[3]) end
        _G[name] = obj
    end
end

-- The game doesn't shout: text stays as written.
function T.Upper(s) return s end

------------------------------------------------------------------------
-- The theme: the accent ("yellow", and its neighbour "orange") is the guild
-- tabard's (herald blue without one; Blizzard's gold only if Core/Accent.lua
-- is missing). T.C and T.HEX change in place, so whatever is drawn
-- after uses them; what's already drawn repaints (Paint and friends, OnAccent).
-- Saved per guild, so it's in place at login before any window is built.
------------------------------------------------------------------------
local HOUSE = {}
for k, h in pairs(T.HEX) do HOUSE[k] = h end
T.A = { face = T.C.yellow, shade = T.C.shade }
local accentUsers = {}
function T:OnAccent(fn) accentUsers[#accentUsers + 1] = fn end

local painted = setmetatable({}, { __mode = "k" })
local function Redo(obj, v)
    local c, a = v[2], v[3]
    if v[1] == "tex" then obj:SetColorTexture(c[1], c[2], c[3], a)
    elseif v[1] == "tint" then obj:SetVertexColor(c[1], c[2], c[3], a)
    elseif v[1] == "ink" then obj:SetTextColor(c[1], c[2], c[3], a)
    elseif v[1] == "fill" then obj:SetBackdropColor(c[1], c[2], c[3], a)
    elseif v[1] == "edge" then obj:SetBackdropBorderColor(c[1], c[2], c[3], a) end
end
local function Mark(kind, obj, c, a)
    if not obj then return end
    local v = { kind, c, a or 1 }
    painted[obj] = v
    Redo(obj, v)
end
function T:Paint(tex, c, a) Mark("tex", tex, c, a) end      -- a texture filled with c
function T:Tint(tex, c, a) Mark("tint", tex, c, a) end      -- a texture's picture tinted c
function T:Ink(fs, c, a) Mark("ink", fs, c, a) end          -- text in c
function T:Fill(f, c, a) Mark("fill", f, c, a) end          -- a backdrop's background
function T:EdgeColor(f, c, a) Mark("edge", f, c, a) end     -- a backdrop's border

-- only the accents follow the theme; the game's art stays the game's
local ROLES = { yellow = "accent", orange = "accent2" }

function T:ApplyPalette(p)
    T.palette = p -- the whole palette (the banner's cloth and band: UI/BrandIcon.lua)
    for key, role in pairs(ROLES) do
        local h = (p and p[role]) or HOUSE[key]
        T.HEX[key] = h
        local c = T.C[key]
        c[1], c[2], c[3] = tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
    end
    ns.GOLD, ns.ORANGE, ns.BLUE = "|cff" .. T.HEX.yellow, "|cff" .. T.HEX.orange, "|cff" .. T.HEX.blue
    for name, spec in pairs(OBJECTS) do
        local font, c = _G[name], spec[2] and T.C[spec[2]]
        if font and font.SetTextColor and c then font:SetTextColor(c[1], c[2], c[3]) end
    end
    for obj, v in pairs(painted) do pcall(Redo, obj, v) end
    for _, fn in ipairs(accentUsers) do pcall(fn) end
end

-- Always the guild's colors (no choice to make); herald blue without a tabard.
function T:UseGuild() return true end

-- Applies a tabard's colors, unless they're exactly the ones on screen.
function T:Use(bg, border, emblem)
    if not ns.Accent then return self:ApplyPalette(nil) end
    local p, now = ns.Accent.Palette(bg, border, emblem), T.palette
    if now and now.accent == p.accent and now.accent2 == p.accent2 and now.cloth == p.cloth and now.band == p.band then return end
    self:ApplyPalette(p)
end

-- This character's last guild colors (kept per character: at login the game
-- often hasn't said which guild you're in yet, and every window built
-- before then would be in the wrong colors).
local function Me()
    local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
    return name and (name .. "-" .. (realm or "")) or nil
end
local function CharThemes()
    local sv = ns.DB and ns.DB.sv
    if not sv then return nil end
    sv.charThemes = sv.charThemes or {}
    return sv.charThemes
end

-- At login (Core.lua, after the saved data loads): the guild's saved colors,
-- else this character's last ones, else herald blue until the tabard is known.
function T:LoadTheme()
    local g = ns.DB and ns.DB.Guild and ns.DB:Guild()
    local chars, me = CharThemes(), Me()
    local saved = (g and g.theme) or (chars and me and chars[me])
    self:Use(saved and saved.bg, saved and saved.border, saved and saved.emblem)
end

-- When the tabard is known (after login) or changes: save and apply it.
-- Outside a guild: herald blue.
function T:RefreshAccent()
    if not ns.Accent then return end
    local ok, bg, border, emblem = pcall(ns.Accent.Tabard, ns.Accent)
    if not ok then return end
    local chars, me = CharThemes(), Me()
    if not bg then
        -- not known yet, or no guild: only a guildless character goes blue
        if IsInGuild and not IsInGuild() then
            if chars and me then chars[me] = nil end
            self:Use(nil, nil, nil)
        end
        return
    end
    local t = { bg = bg, border = border, emblem = emblem }
    local g = ns.DB and ns.DB.Guild and ns.DB:Guild()
    if g then g.theme = t end
    if chars and me then chars[me] = t end
    self:Use(bg, border, emblem)
end

------------------------------------------------------------------------
-- Windows and controls: the game's own. A window only keeps the accent
-- fresh (the tabard can load after login).
------------------------------------------------------------------------
function T:Skin(frame)
    if not frame or frame._ngmSkinned then return frame end
    frame._ngmSkinned = true
    frame:HookScript("OnShow", function() T:RefreshAccent() end)
    return frame
end

function T:SkinButton(b) return b end

-- A thin line in the theme's edge colour (used by T:Edge's callers for a
-- frame around something, e.g. the Guild window shortcut's highlight).
function T:Edge(host, anchor, thick, color, layer, sublevel)
    local parts = {}
    local function Strip()
        local x = host:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
        parts[#parts + 1] = x
        return x
    end
    local top, bottom, left, right = Strip(), Strip(), Strip(), Strip()
    top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT"); top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT"); top:SetHeight(thick)
    bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT"); bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT"); bottom:SetHeight(thick)
    left:SetPoint("TOPRIGHT", anchor, "TOPLEFT"); left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT"); left:SetWidth(thick)
    right:SetPoint("TOPLEFT", anchor, "TOPRIGHT"); right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT"); right:SetWidth(thick)
    local e = { parts = parts }
    function e:SetColor(c, a) for _, x in ipairs(parts) do T:Paint(x, c, a) end end
    function e:SetShown(on) for _, x in ipairs(parts) do x:SetShown(on) end end
    e:SetColor(color or T.C.edge)
    return e
end

-- A panel, as the game's tooltips: dark, with the tooltip border.
function T:Box(frame)
    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetAllPoints(frame)
    b:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetBackdropColor(0.05, 0.04, 0.03, 0.85)
    b:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
    return b
end

-- A thin divider beside a heading.
function T:Dashes(host, layer)
    local tex = host:CreateTexture(nil, layer or "ARTWORK")
    tex:SetHeight(1)
    T:Paint(tex, T.C.edge, 0.8)
    tex.Fit = function() end
    return tex
end

------------------------------------------------------------------------
-- Toast: a short banner at the top of the screen, faded in and out, in the
-- game's dialog look.
------------------------------------------------------------------------
local toast
function T:Toast(title, text)
    if not toast then
        toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        toast:SetSize(360, 70)
        toast:SetPoint("TOP", 0, -50)
        toast:SetFrameStrata("DIALOG")
        toast:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                            tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        toast.title = toast:CreateFontString(nil, "OVERLAY", "NGMFontHuge")
        toast.title:SetPoint("TOP", 0, -14)
        toast.text = toast:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        toast.text:SetPoint("TOP", toast.title, "BOTTOM", 0, -6)
        toast.text:SetWidth(330)
        local fade = toast:CreateAnimationGroup()
        local a = fade:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.25)
        toast.fade = fade
    end
    toast.title:SetText(title or "")
    toast.text:SetText(text or "")
    toast:SetHeight(text and text ~= "" and 70 or 48)
    toast:Show()
    toast.fade:Stop(); toast.fade:Play()
    toast.shown = (toast.shown or 0) + 1
    local mine = toast.shown
    C_Timer.After(3.5, function() if toast.shown == mine then toast:Hide() end end)
end
