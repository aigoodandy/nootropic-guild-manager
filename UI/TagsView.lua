--[[
    Nootropic Guild Manager - Tags tab (officers only)
    Create, rename, recolor, reorder and delete the guild's tags (shared with
    everyone using the addon),
    plus a search reference.
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local TV = {}
ns.TagsView = TV

local ROW_H = 30
local LIST_W = 520

function TV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page = page
    page:SetScript("OnShow", function() TV:Refresh() end)

    local intro = page:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", 78, -38)
    intro:SetText("Tags are shared with everyone in the guild using the addon. Click a tag's name to find everyone who has it.")

    local new = W.Button(page, "New Tag", 100, 22)
    new:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    new:SetScript("OnClick", function() ns.TagEditor:Open(nil) end)

    -- Tag list
    local inset = frame.Inset
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    header:SetSize(LIST_W, 24)
    local cols = { { "Tag", 250 }, { "Members", 90 }, { "", LIST_W - 340 } }
    local x = 0
    for _, c in ipairs(cols) do
        local h = W.ColumnHeader(header, c[1], c[2])
        h:SetPoint("TOPLEFT", x, 0)
        h:EnableMouse(false)
        x = x + c[2]
    end

    local scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scrollBox:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 4)
    scrollBox:SetWidth(LIST_W)
    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Frame", function(row, item) TV:InitRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.emptyText = page:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisable")
    self.emptyText:SetPoint("CENTER", scrollBox, "CENTER")

    self:BuildHelp(page, inset, scrollBar)

    ns:On("TAGS_CHANGED", function() if page:IsVisible() then TV:Refresh() end end)
    ns:On("ROSTER_UPDATED", function()
        if page:IsVisible() then ns.Debounce("tagsview", 0.2, function() TV:Refresh() end) end
    end)
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function SmallIconButton(parent, normal, pushed, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:SetNormalTexture(normal)
    b:SetPushedTexture(pushed)
    b:SetDisabledTexture(normal)
    b:GetDisabledTexture():SetDesaturated(true)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W.Tooltip(b, tip)
    return b
end

local function BuildRow(row)
    row:SetHeight(ROW_H)
    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetColorTexture(1, 1, 1, 0.035)

    -- the tag's icon with its color as a border; click to pick another icon
    row.IconBtn = CreateFrame("Button", nil, row)
    row.IconBtn:SetSize(22, 22)
    row.IconBtn:SetPoint("LEFT", 8, 0)
    row.IconBtn.Tag = W.TagIcon(row.IconBtn, 22)
    row.IconBtn.Tag:SetAllPoints()
    row.IconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.IconBtn:SetScript("OnClick", function(self)
        local tag = row.tag
        if not tag then return end
        ns.IconPicker:Open(D:TagIcon(tag), function(icon)
            local _, err = ns.DB:SetTagIcon(tag.id, icon)
            if err then ns:Print("|cffff5555" .. err .. "|r") end
        end, self)
    end)
    W.Tooltip(row.IconBtn, "Change icon")

    row.Pill = W.Pill(row, 18, 16)
    row.Pill:SetPoint("LEFT", row.IconBtn, "RIGHT", 10, 0)
    row.Pill:SetScript("OnClick", function()
        if row.tag then ns.UI:ShowRosterWithSearch(('tag:"%s"'):format(row.tag.name:lower())) end
    end)
    W.Tooltip(row.Pill, "Show members with this tag")

    row.Count = row:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    row.Count:SetPoint("LEFT", 258, 0)

    row.Delete = W.Button(row, "Delete", 64, 20)
    row.Delete:SetPoint("RIGHT", -6, 0)
    row.Delete:SetScript("OnClick", function()
        local tag = row.tag
        if not tag then return end
        W.Confirm(("Delete the tag \"%s\"?\nIt will be removed from every member."):format(tag.name), function()
            ns.DB:DeleteTag(tag.id)
        end)
    end)

    row.Rename = W.Button(row, "Edit", 70, 20)
    row.Rename:SetPoint("RIGHT", row.Delete, "LEFT", -4, 0)
    row.Rename:SetScript("OnClick", function()
        if row.tag then ns.TagEditor:Open(row.tag) end
    end)
    W.Tooltip(row.Rename, "Edit tag", "Change the name, icon and color.")

    row.Down = SmallIconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down", "Move down")
    row.Down:SetPoint("RIGHT", row.Rename, "LEFT", -6, 0)
    row.Down:SetScript("OnClick", function() if row.tag then ns.DB:MoveTag(row.tag.id, 1) end end)

    row.Up = SmallIconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up", "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down", "Move up")
    row.Up:SetPoint("RIGHT", row.Down, "LEFT", 0, 0)
    row.Up:SetScript("OnClick", function() if row.tag then ns.DB:MoveTag(row.tag.id, -1) end end)
end

function TV:InitRow(row, item)
    if not row.built then
        BuildRow(row)
        row.built = true
    end
    local tag = item.tag
    row.tag = tag
    row.Stripe:SetShown(item.stripe)
    row.IconBtn.Tag:SetTag(tag)
    row.Pill:SetTag(tag)
    local n = ns.Roster:TagCount(tag.id)
    row.Count:SetText(n == 1 and "1 member" or (n .. " members"))
    row.Up:SetEnabled(not item.first)
    row.Down:SetEnabled(not item.last)
end

------------------------------------------------------------------------
-- Search reference panel
------------------------------------------------------------------------
function TV:BuildHelp(page, inset, leftOf)
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    self.help = box
    box:SetPoint("TOPLEFT", leftOf, "TOPRIGHT", 16, 26)
    box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -8, 8)
    box:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.35)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local title = box:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("Searching the Roster")

    local Y = "|cffffd100"
    local body = box:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", -14, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetText(table.concat({
        "Type any words. A member is shown when every word matches their name, class, spec, professions or tags.",
        "",
        Y .. "warrior protection|r   prot warriors",
        Y .. "tailoring enchanting|r   both professions",
        "",
        "Limit a word to one field:",
        Y .. "name:  tag:  prof:  spec:  class:|r",
        Y .. "rank:  zone:  note:|r",
        "",
        "Mains and alts:",
        Y .. "main:markpri|r   Markpri and all their alts",
        Y .. "is:alt|r  " .. Y .. "is:main|r   only alts / only mains",
        Y .. "is:addon|r   guildmates using the addon",
        "",
        "Numbers:",
        Y .. "rating:4|r   four stars or better",
        Y .. "rating<2|r   one star or unrated",
        Y .. "level>=55|r   level 55 and up",
        "",
        "Exclude with a minus:  " .. Y .. "-raiding|r",
        "Keep phrases together:  " .. Y .. "tag:\"world pvp\"|r",
    }, "\n"))
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
-- The search reference only shows when the window is wide enough for it.
function TV:OnResize(width)
    if self.help then self.help:SetShown(width >= 820) end
end

function TV:Refresh()
    if self.page and not ns.IsOfficer() then
        self.page:Hide() -- officers only; the tab is hidden for everyone else
        return
    end
    if not self.page then return end
    local tags = ns.DB:GetTags()
    local list = {}
    for i, tag in ipairs(tags) do
        list[i] = { tag = tag, stripe = (i % 2 == 0), first = (i == 1), last = (i == #tags) }
    end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(list), retain)
    if not ns.DB:Guild() then
        self.emptyText:SetText("Join a guild to manage tags.")
    elseif #list == 0 then
        self.emptyText:SetText("No tags yet. Click New Tag to create one.")
    else
        self.emptyText:SetText("")
    end
end
