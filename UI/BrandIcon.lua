--[[
    Nootropic Guild Manager - Brand icon
    One renderer for the addon's icon wherever it appears (window portrait,
    minimap button, Guild & Communities shortcut, options previews).
    Always NGM's herald banner in the guild's colors: four layers
    (Media/Banner*.tga, from docs/Banner*.svg): a round dark field with a
    gilt ring, the cloth (tinted the tabard's background), its edge (tinted
    the border) and the rod, stitching and wax seal on top. Herald blue
    without a tabard.

      ns.Brand:AttachPortrait(frame)                 -- window portrait
      ns.Brand:Attach(host, size, point, opts)       -- anywhere else

]]
local _, ns = ...
local Brand = {}
ns.Brand = Brand

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MEDIA = "Interface\\AddOns\\NootropicGuildManager\\Media\\"

Brand.icons = {}

-- NGM's banner, always: the cloth in the guild tabard's background color,
-- its edge in the border's (herald blue without a tabard). The same banner
-- and colors as on ngmpeon.app (Core/Accent.lua Palette).
function Brand:Style() return "banner" end

local function Tint(tex, hex)
    tex:SetVertexColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
end

local IconMixin = {}

function IconMixin:Apply()
    local p = ns.Theme and ns.Theme.palette
    Tint(self.Cloth, p and p.cloth or ns.Accent.HERALD.cloth)
    Tint(self.Band, p and p.band or ns.Accent.HERALD.band)
    -- `crop`: trim the banner's own gold ring where the host already draws
    -- a round border (the minimap button), so there's one ring
    local c = self.crop or 0
    for _, t in ipairs(self.layers) do t:SetTexCoord(c, 1 - c, c, 1 - c) end
end

--[[
    host:  frame the textures are drawn on (so they layer with its own art)
    size:  icon size in pixels
    point: { point, relativeTo, relativePoint, x, y } for the icon
    opts:  layer (default ARTWORK), round (default true), style (fixed style),
           crop (0-0.5: trim that much off each edge of the medallion art)
]]
function Brand:Attach(host, size, point, opts)
    opts = opts or {}
    local layer = opts.layer or "ARTWORK"
    local icon = { host = host, size = size, crop = opts.crop, layers = {} }
    for k, v in pairs(IconMixin) do icon[k] = v end

    -- Reference square everything is placed against.
    local slot = host:CreateTexture(nil, "BACKGROUND")
    slot:SetSize(size, size)
    slot:SetPoint(unpack(point))
    slot:SetColorTexture(0, 0, 0, 0)
    icon.Slot = slot

    -- the round field and ring, the cloth, its edge, then the rod, stitching and seal
    for n, name in ipairs({ "Base", "Cloth", "Band", "Top" }) do
        local t = host:CreateTexture(nil, layer, nil, n)
        t:SetTexture(MEDIA .. "Banner" .. name)
        t:SetAllPoints(slot)
        icon[name] = t
        icon.layers[#icon.layers + 1] = t
    end

    if opts.round ~= false and host.CreateMaskTexture then
        local mask = host:CreateMaskTexture()
        if mask then
            mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(slot)
            for _, t in ipairs(icon.layers) do
                if t.AddMaskTexture then t:AddMaskTexture(mask) end
            end
        end
    end

    table.insert(self.icons, icon)
    icon:Apply()
    return icon
end

-- Window portrait, placed exactly like Blizzard's guild portrait overlay.
function Brand:AttachPortrait(frame)
    local p = (frame.PortraitContainer and frame.PortraitContainer.portrait) or frame.portrait or frame.Portrait
    if p then p:Hide() end
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 300)
    overlay:EnableMouse(false)
    local icon = self:Attach(overlay, 60, { "TOPLEFT", overlay, "TOPLEFT", -5, 8 }, { layer = "BACKGROUND" })
    icon.Overlay = overlay
    return icon
end

function Brand:Refresh()
    for _, icon in ipairs(self.icons) do icon:Apply() end
    ns:Fire("BRAND_CHANGED")
end

function Brand:Init()
    -- the banner wears the guild's colors: repaint when they change
    ns.Theme:OnAccent(function() Brand:Refresh() end)
    -- the tabard isn't known until guild data arrives, and it can change
    local function queue() ns.Debounce("accent", 0.5, function() ns.Theme:RefreshAccent() end) end
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", queue)
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", queue)
    queue()
end
