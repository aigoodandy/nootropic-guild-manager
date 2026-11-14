--[[
    Nootropic Guild Manager - Who Can Craft window
    Search every recipe guildmates share (Services/Recipes.lua) and see who
    can make it, online crafters first. Opened with a member, it lists that
    member's recipes instead.

    ns.RecipesView:Open()                 search the whole guild
    ns.RecipesView:Open({ text = "..." }) start with a search
    ns.RecipesView:Open({ member = full }) one member's recipes
]]
local _, ns = ...
local W = ns.Widgets
local RV = {}
ns.RecipesView = RV

local ROW_H = 22
local MAX_RESULTS = 300
local GREEN, GRAY = "|cff20ff20", "|cff9d9d9d"

function RV:Build()
    local f = CreateFrame("Frame", "NootropicGMRecipesWindow", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(520, 480)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f

    local search = CreateFrame("EditBox", "NootropicGMRecipesSearch", f, "SearchBoxTemplate")
    search:SetSize(260, 20)
    search:SetPoint("TOPLEFT", 16, -32)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText("Search recipes, e.g. flask, bracers...") end
    search:HookScript("OnTextChanged", function() ns.Debounce("recipesearch", 0.15, function() RV:Refresh() end) end)
    self.search = search

    self.who = W.Pill(f, 18, 22)
    self.who:SetPoint("LEFT", search, "RIGHT", 10, 0)
    self.who:SetScript("OnClick", function() RV.member = nil; RV:Refresh() end)
    W.Tooltip(self.who, "Showing one character's recipes", "Click to search the whole guild.")
    self.who:Hide()

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -60)
    scrollBox:SetPoint("BOTTOMRIGHT", -26, 34)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, e) RV:InitRow(row, e) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    self.empty = f:CreateFontString(nil, "OVERLAY", "NGMFontDim")
    self.empty:SetPoint("CENTER", scrollBox, "CENTER")
    self.empty:SetWidth(420)

    self.summary = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.summary:SetPoint("BOTTOMLEFT", 16, 12)
    self.summary:SetPoint("BOTTOMRIGHT", -16, 12)
    self.summary:SetJustifyH("LEFT")

    ns:On("RECIPES_CHANGED", function() if f:IsShown() then RV:Refresh() end end)
    ns:On("ROSTER_UPDATED", function() if f:IsShown() then ns.Debounce("recipesroster", 0.5, function() RV:Refresh() end) end end)
end

local function Online(full) local e = ns.Roster.byName[full]; return e and e.online end

local function CrafterText(r, max)
    local parts = {}
    for i, full in ipairs(r.crafters) do
        if i > max then
            parts[#parts + 1] = GRAY .. "+" .. (#r.crafters - max) .. "|r"
            break
        end
        parts[#parts + 1] = (Online(full) and GREEN or GRAY) .. ns.ShortName(full) .. "|r"
    end
    return table.concat(parts, ", ")
end

function RV:InitRow(row, r)
    if not row.built then
        row.built = true
        row:SetHeight(ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(16, 16)
        row.Icon:SetPoint("LEFT", 4, 0)
        row.Name = row:CreateFontString(nil, "OVERLAY", "NGMFontText")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
        row.Name:SetWidth(210)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.Who = row:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        row.Who:SetPoint("LEFT", row.Name, "RIGHT", 6, 0)
        row.Who:SetPoint("RIGHT", -6, 0)
        row.Who:SetJustifyH("LEFT")
        row.Who:SetWordWrap(false)
        row:SetScript("OnClick", function(self) RV:ShowRowMenu(self, self.entry) end)
        row:SetScript("OnEnter", function(self) RV:ShowRowTooltip(self, self.entry) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.entry = r
    W.SetIcon(row.Icon, ns.Recipes.RecipeIcon(r.id))
    row.Name:SetText(r.name)
    row.Who:SetText(RV.member and (GRAY .. r.prof .. "|r") or CrafterText(r, 3))
end

function RV:ShowRowTooltip(row, r)
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellByID then
        pcall(GameTooltip.SetSpellByID, GameTooltip, r.id)
    else
        GameTooltip:AddLine(r.name)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Known by %d guildmate%s (%s):"):format(#r.crafters, #r.crafters == 1 and "" or "s", r.prof), ns.Theme.C.yellow[1], ns.Theme.C.yellow[2], ns.Theme.C.yellow[3])
    for i, full in ipairs(r.crafters) do
        if i > 15 then GameTooltip:AddLine(("...and %d more"):format(#r.crafters - 15), 0.6, 0.6, 0.6) break end
        GameTooltip:AddLine(ns.ShortName(full) .. (Online(full) and "  |cff20ff20online|r" or ""), 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open a crafter's profile.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function RV:ShowRowMenu(row, r)
    if not r then return end
    if #r.crafters == 1 then
        ns.DetailPanel:Show(r.crafters[1], ns.UI.frame)
        return
    end
    local items = { { text = r.name, isTitle = true } }
    for i, full in ipairs(r.crafters) do
        if i > 25 then break end
        items[#items + 1] = { text = ns.ShortName(full) .. (Online(full) and "  |cff20ff20online|r" or ""),
            func = function() ns.DetailPanel:Show(full, ns.UI.frame) end }
    end
    W.ShowMenu(row, items)
end

function RV:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local text = ns.Trim(self.search:GetText() or "")
    W.SetTitle(self.frame, self.member and ("Recipes: " .. ns.ShortName(self.member)) or "Who Can Craft It?")
    if self.member then
        self.who:SetLabel(ns.ShortName(self.member) .. "  x")
        self.who:Show()
    else
        self.who:Hide()
    end
    local list = {}
    if self.member or #text >= 2 then list = ns.Recipes:Search(text, self.member) end
    local shown = list
    if #list > MAX_RESULTS then
        shown = {}
        for i = 1, MAX_RESULTS do shown[i] = list[i] end
    end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.scrollBox:SetDataProvider(CreateDataProvider(shown), retain)

    local crafters = {}
    for _, l in ipairs(ns.Recipes:AllLists()) do crafters[l.full] = true end
    local n = 0
    for _ in pairs(crafters) do n = n + 1 end
    if self.member then
        self.empty:SetText(#list == 0 and ((text ~= "" and "No matching recipes." or "They haven't shared any recipes yet.") .. "\n\n" .. GRAY .. "Recipes are shared when they open a profession window with the addon running.|r") or "")
    elseif #text < 2 then
        self.empty:SetText(n == 0
            and ("Nobody has shared recipes yet.\n\n" .. GRAY .. "Recipes are shared automatically when a guildmate with the addon opens one of their profession windows.|r")
            or ("Type at least two letters of a recipe or item name.\n\n" .. GRAY .. "Searching recipes shared by " .. n .. " guildmate" .. (n == 1 and "" or "s") .. ".|r"))
    else
        self.empty:SetText(#list == 0 and "Nobody in the guild has shared that recipe." or "")
    end
    self.summary:SetText(#list > MAX_RESULTS and (("Showing %d of %d recipes; type more to narrow it down."):format(MAX_RESULTS, #list))
        or (#list > 0 and (("%d recipe%s"):format(#list, #list == 1 and "" or "s")) or ""))
end

function RV:Open(opts)
    opts = opts or {}
    if not self.frame then self:Build() end
    self.member = opts.member
    local f = self.frame
    if not f:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end
    self.search:SetText(opts.text or "")
    f:Show()
    self:Refresh()
    if not opts.member then self.search:SetFocus() end
end
