-- Test: the Guild window shortcut starts up, places itself under Blizzard's
-- side tabs (found by where they are, whatever they're called), and
-- /ngm diag runs through. (Test 25 lost its setup functions in an edit and
-- stopped the addon's whole start-up: this would have caught it.)
local ROOT = arg[1]
local ns = {}
local printed = {}
ns.Print = function(_, m) printed[#printed + 1] = m end
ns.Fire = function() end
ns.RegisterEvent = function() end
ns.DB = { Settings = function() return {} end }
ns.Theme = { C = setmetatable({}, { __index = function() return { 0, 0, 0 } end }), Paint = function() end,
  Edge = function() return { SetColor = function() end } end }
ns.Brand = { Attach = function() return { Apply = function() end } end, Style = function() return "banner" end }
ns.UI = { Show = function() end, Title = function() return "NGM" end }
C_Timer = { After = function(_, fn) fn() end }
hooksecurefunc = function() end

-- frames: just enough of the game's
local function Frame(parent, x, y, w, h)
    local f = { parent = parent, x = x or 0, y = y or 0, w = w or 32, h = h or 32, shown = true, kids = {}, scripts = {}, level = 1 }
    if parent then table.insert(parent.kids, f) end
    local m = {}
    function m:GetParent() return self.parent end
    function m:GetChildren() return unpack(self.kids) end
    function m:IsShown() return self.shown end
    function m:IsVisible() return self.shown end
    function m:SetShown(on) self.shown = on end
    function m:GetLeft() return self.x end
    function m:GetRight() return self.x + self.w end
    function m:GetBottom() return self.y end
    function m:GetTop() return self.y + self.h end
    function m:SetSize(w, h) self.w, self.h = w, h end
    function m:GetWidth() return self.w end
    function m:GetHeight() return self.h end
    function m:GetCenter() return self.x + self.w / 2, self.y + self.h / 2 end
    function m:GetFrameLevel() return self.level end
    function m:SetFrameLevel(l) self.level = l end
    function m:GetName() return self.name end
    function m:ClearAllPoints() self.anchor = nil end
    function m:SetPoint(_, rel, _, dx, dy) self.anchor = { rel = rel, dy = dy } end
    function m:GetPoint() return "TOPLEFT", self.anchor and self.anchor.rel end
    function m:HookScript(k, fn) self.scripts[k] = fn end
    function m:SetScript(k, fn) self.scripts[k] = fn end
    function m:CreateTexture() return setmetatable({}, { __index = function() return function() end end }) end
    return setmetatable(f, { __index = function(_, k) return m[k] or function() end end })
end
CreateFrame = function(_, _, parent) return Frame(parent, 600, 300) end

-- the Guild window (right edge at 500) and three of Blizzard's tabs down its side
CommunitiesFrame = Frame(nil, 0, 0, 500, 400)
local chat = Frame(CommunitiesFrame, 502, 340); chat.name = "ChatTab"
local roster = Frame(CommunitiesFrame, 502, 300); roster.name = "RosterTab"
local play = Frame(CommunitiesFrame, 502, 260); play.name = "PreferredPlaySettings" -- not a name the old list knew
local content = Frame(CommunitiesFrame, 10, 10, 400, 300) -- the window's own contents: not a tab

assert(loadfile(ROOT .. "/UI/Communities.lua"))("NGM", ns)
local CM = ns.Communities
CM:Init()
local b = CM.buttons.CommunitiesFrame
assert(b, "the shortcut is made")
assert(b.anchor and b.anchor.rel == play, "under the lowest tab showing (Preferred Play Settings)")
assert(b.anchor.dy == -8, "spaced as theirs are (8 apart here), got " .. tostring(b.anchor.dy))
play.shown = false
play.scripts.OnHide()
assert(b.anchor.rel == roster, "that tab hides: under the next one up")
CM:Diagnose()
assert(#printed >= 2, "/ngm diag runs through")
print("OK")
