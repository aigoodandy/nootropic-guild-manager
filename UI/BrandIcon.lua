--[[
    Nootropic Guild Manager - Brand icon
    One renderer for the addon's icon wherever it appears (window portrait,
    minimap button, Guild & Communities shortcut, options previews).
    Styles: an ale mug, a Brewfest stein, or your guild's emblem.

    The layout copies Blizzard's own guild portrait (CommunitiesFrame
    PortraitOverlay): a 60x60 circle, the tabard background and border from
    Interface\GuildFrame\GuildFrame, and a 56x64 emblem centered on top.
    Everything scales from that 60px reference.

      ns.Brand:AttachPortrait(frame)                 -- window portrait
      ns.Brand:Attach(host, size, point, opts)       -- anywhere else
]]
local _, ns = ...
local D = ns.Data
local Brand = {}
ns.Brand = Brand

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GUILD_ART = "Interface\\GuildFrame\\GuildFrame"
local BG_COORDS = { 0.63183594, 0.69238281, 0.61914063, 0.74023438 }
local BORDER_COORDS = { 0.63183594, 0.69238281, 0.74414063, 0.86523438 }

Brand.icons = {}

function Brand:Style()
    return ns.DB:Settings().iconStyle or "mug"
end

-- True when there's a guild tabard to draw.
function Brand:CanShowEmblem()
    if not IsInGuild() or not SetLargeGuildTabardTextures then return false end
    if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
        local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
        if ok and info == nil then return false end
    end
    return true
end

local IconMixin = {}

function IconMixin:ShowEmblem(on)
    self.Bg:SetShown(on)
    self.Border:SetShown(on)
    self.Emblem:SetShown(on)
    self.Icon:SetShown(not on)
end

function IconMixin:Apply()
    local key = self.fixedStyle or Brand:Style()
    if key == "emblem" and Brand:CanShowEmblem() then
        local s = self.size / 60
        self.Bg:SetTexture(GUILD_ART)
        self.Bg:SetTexCoord(unpack(BG_COORDS))
        self.Border:SetTexture(GUILD_ART)
        self.Border:SetTexCoord(unpack(BORDER_COORDS))
        self.Emblem:SetSize(56 * s, 64 * s) -- the game sets width from height (7:8)
        local ok = pcall(SetLargeGuildTabardTextures, "player", self.Emblem, self.Bg, self.Border)
        if ok then
            self:ShowEmblem(true)
            return
        end
    end
    self:ShowEmblem(false)
    local style = D:IconStyle(key)
    self.Icon:SetTexture(style.icon or D.DEFAULT_ICON)
    self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

--[[
    host:  frame the textures are drawn on (so they layer with its own art)
    size:  icon size in pixels
    point: { point, relativeTo, relativePoint, x, y } for the icon's top-left
    opts:  layer (default ARTWORK), round (default true), style (fixed style)
]]
function Brand:Attach(host, size, point, opts)
    opts = opts or {}
    local layer = opts.layer or "ARTWORK"
    local s = size / 60
    local icon = { host = host, size = size, fixedStyle = opts.style }
    for k, v in pairs(IconMixin) do icon[k] = v end

    -- Reference square everything is placed against.
    local slot = host:CreateTexture(nil, "BACKGROUND")
    slot:SetSize(size, size)
    slot:SetPoint(unpack(point))
    slot:SetColorTexture(0, 0, 0, 0)
    icon.Slot = slot

    icon.Icon = host:CreateTexture(nil, layer, nil, 1)
    icon.Icon:SetAllPoints(slot)
    icon.Bg = host:CreateTexture(nil, layer, nil, 1)
    icon.Bg:SetAllPoints(slot)
    icon.Emblem = host:CreateTexture(nil, layer, nil, 2)
    icon.Emblem:SetSize(56 * s, 64 * s)
    icon.Emblem:SetPoint("CENTER", slot, "CENTER", 0, 1 * s)
    icon.Border = host:CreateTexture(nil, layer, nil, 3)
    icon.Border:SetSize(size, 59 * s)
    icon.Border:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -1 * s)

    if opts.round ~= false and host.CreateMaskTexture then
        local mask = host:CreateMaskTexture()
        if mask then
            mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(slot)
            for _, t in ipairs({ icon.Icon, icon.Bg, icon.Emblem, icon.Border }) do
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

function Brand:SetStyle(key)
    ns.DB:Settings().iconStyle = key
    self:Refresh()
end

function Brand:Init()
    -- The emblem isn't known until guild data arrives, and it can change.
    local function queue()
        if Brand:Style() == "emblem" then ns.Debounce("brand", 0.5, function() Brand:Refresh() end) end
    end
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", queue)
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", queue)
    queue()
end
