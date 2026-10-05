--[[
    Nootropic Guild Manager - Tag editor (officers)
    Creates a tag or edits one: its name, its icon (any macro icon) and its
    color (picked from the tag palette).
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local TE = {}
ns.TagEditor = TE

function TE:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "NootropicGMTagEditor", UIParent, "BackdropTemplate")
    f:SetSize(360, 252)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    f:Hide()
    f:SetScript("OnHide", function() ns.IconPicker:Hide() end)
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f

    self.title = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
    self.title:SetPoint("TOP", 0, -18)

    -- Icon (click to choose)
    local icon = CreateFrame("Button", nil, f, "BackdropTemplate")
    icon:SetSize(48, 48)
    icon:SetPoint("TOPLEFT", 26, -48)
    icon:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 2 })
    icon.Tex = icon:CreateTexture(nil, "ARTWORK")
    icon.Tex:SetPoint("TOPLEFT", 2, -2)
    icon.Tex:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.Tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnClick", function(self)
        ns.IconPicker:Open(TE:DisplayIcon(), function(chosen)
            TE.icon = chosen
            TE:Update()
        end, f)
    end)
    W.Tooltip(icon, "Choose an icon", "Any icon from the macro icon menu.")
    self.iconButton = icon
    local iconHint = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    iconHint:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    iconHint:SetText("Change")

    -- Name
    local nameLabel = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", icon, "TOPRIGHT", 18, 0)
    nameLabel:SetText("Name")
    local name = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    name:SetSize(220, 20)
    name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    name:SetAutoFocus(false)
    name:SetMaxLetters(D.MAX_TAG_LENGTH)
    name:SetScript("OnTextChanged", function() TE:Update() end)
    name:SetScript("OnEnterPressed", function() TE:Save() end)
    name:SetScript("OnEscapePressed", function() f:Hide() end)
    self.nameBox = name

    -- Color (dropdown of the tag palette)
    local colorLabel = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -10)
    colorLabel:SetText("Color")
    local color = W.Button(f, "", 140, 22)
    color:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -4)
    color.Arrow = color:CreateTexture(nil, "OVERLAY")
    color.Arrow:SetSize(18, 18)
    color.Arrow:SetPoint("RIGHT", -4, 0)
    color.Arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    color:SetScript("OnClick", function(self)
        local items = { { text = "Tag color", isTitle = true } }
        for i, c in ipairs(D.TAG_COLORS) do
            items[#items + 1] = {
                text = D:TagColorHex(i) .. c.name .. "|r",
                radio = true,
                checked = function() return TE.color == i end,
                func = function()
                    TE.color = i
                    TE:Update()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    self.colorButton = color

    -- Preview
    local prevLabel = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormalSmall")
    prevLabel:SetPoint("TOPLEFT", 26, -142)
    prevLabel:SetText("Preview")
    self.preview = W.Pill(f, 20, 16)
    self.preview:SetPoint("LEFT", prevLabel, "RIGHT", 12, 0)
    self.preview:EnableMouse(false)
    self.previewIcon = W.TagIcon(f, 20)
    self.previewIcon:SetPoint("LEFT", self.preview, "RIGHT", 14, 0)
    local roster = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontDisableSmall")
    roster:SetPoint("LEFT", self.previewIcon, "RIGHT", 6, 0)
    roster:SetText("(roster column)")

    self.error = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    self.error:SetPoint("TOPLEFT", 26, -172)
    self.error:SetPoint("RIGHT", -26, 0)
    self.error:SetJustifyH("LEFT")
    self.error:SetTextColor(1, 0.35, 0.35)

    local save = W.Button(f, SAVE or "Save", 100, 22)
    save:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 20)
    save:SetScript("OnClick", function() TE:Save() end)
    self.saveButton = save
    local cancel = W.Button(f, CANCEL or "Cancel", 100, 22)
    cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 20)
    cancel:SetScript("OnClick", function() f:Hide() end)
    return f
end

-- The icon shown: the one just picked, the tag's current icon, or a question mark.
function TE:DisplayIcon()
    if self.icon then return self.icon end
    local tag = self.tagId and ns.DB:GetTag(self.tagId)
    return tag and D:TagIcon(tag) or D.UNKNOWN_ICON
end

function TE:Update()
    local icon = self:DisplayIcon()
    local r, g, b = D:TagColor(self.color)
    self.iconButton.Tex:SetTexture(icon)
    self.iconButton:SetBackdropBorderColor(r, g, b, 1)
    self.colorButton:SetText(D:TagColorHex(self.color) .. (D.TAG_COLORS[self.color] or D.TAG_COLORS[1]).name .. "|r")
    local text = ns.Trim(self.nameBox:GetText())
    local fake = { name = text ~= "" and text or "Tag name", color = self.color, icon = icon }
    self.preview:SetTag(fake)
    self.previewIcon:SetTag(fake)
    self.saveButton:SetEnabled(text ~= "")
end

function TE:Save()
    local text = self.nameBox:GetText()
    local _, err
    if self.tagId then
        _, err = ns.DB:UpdateTag(self.tagId, ns.Trim(text), self.color, self.icon)
    else
        _, err = ns.DB:CreateTag(text, self.color, self.icon)
    end
    if err then
        self.error:SetText(err)
        return
    end
    self.frame:Hide()
end

-- tag: the tag to edit, or nil for a new one.
function TE:Open(tag)
    if not ns.DB:CanManageTags() then
        ns:Print("|cffff5555Only officers can manage tags.|r")
        return
    end
    local f = self:Build()
    self.tagId = tag and tag.id
    self.icon = nil
    if tag then
        self.color = tag.color
    else
        self.color = (#ns.DB:GetTags() % #D.TAG_COLORS) + 1
    end
    self.title:SetText(tag and ("Edit Tag: " .. tag.name) or "New Tag")
    self.nameBox:SetText(tag and tag.name or "")
    self.error:SetText("")
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:Show()
    self:Update()
    self.nameBox:SetFocus()
    self.nameBox:HighlightText()
end
