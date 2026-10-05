--[[
    Nootropic Guild Manager - Info tab
    Edit the guild message of the day and guild information side by side
    with the guild news feed. Shows a chat preview of the MOTD, character
    counts, unsaved-change warnings, and read-only state for ranks that
    can't edit.
]]
local _, ns = ...
local W = ns.Widgets
local IV = {}
ns.InfoView = IV

local NEWS_ROW_H = 20

------------------------------------------------------------------------
-- Cards
------------------------------------------------------------------------
local function Card(parent, title)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    c:SetBackdropColor(0, 0, 0, 0.35)
    c:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    c.Title, c.Line = W.SectionHeader(c, title)
    c.Title:SetPoint("TOPLEFT", 12, -10)
    c.Line:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    return c
end

-- An editable text card: editor, counter, status, Revert / Save.
-- opts.command(text) -> slash command line: Save runs it through a secure button.
-- opts.external: Save opens Blizzard's Guild window (paste the draft there).
local function TextCard(parent, title, maxLetters, getter, canEdit, opts)
    local c = Card(parent, title)
    c.getter, c.canEdit, c.max, c.opts = getter, canEdit, maxLetters, opts

    c.Lock = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.Lock:SetPoint("LEFT", c.Title, "RIGHT", 8, 0)
    c.Lock:SetText("|TInterface\\Buttons\\LockButton-Locked-Up:14|t read only for your rank")
    c.Line:SetPoint("LEFT", c.Lock, "RIGHT", 6, 0)

    c.Save = W.Button(c, "Save", 70, 22)
    c.Save:SetPoint("BOTTOMRIGHT", -10, 10)
    c.Revert = W.Button(c, "Revert", 70, 22)
    c.Revert:SetPoint("RIGHT", c.Save, "LEFT", -6, 0)

    c.Count = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.Count:SetPoint("BOTTOMLEFT", 14, 16)
    c.Status = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.Status:SetPoint("LEFT", c.Count, "RIGHT", 12, 0)

    c.Editor, c.Box = W.ScrollEditor(c, maxLetters)
    c.Editor:SetPoint("TOPLEFT", 16, -32)
    c.Editor:SetPoint("BOTTOMRIGHT", -16, 40)

    function c:IsDirty()
        return (self.Box:GetText() or "") ~= (self.saved or "")
    end

    function c:UpdateState()
        local len = #(self.Box:GetText() or "")
        local editable = self.canEdit()
        self.Count:SetText(("%d / %d"):format(len, self.max))
        self.Lock:SetShown(not editable)
        self.Box:EnableMouse(editable)
        self.Box:SetTextColor(editable and 1 or 0.75, editable and 1 or 0.75, editable and 1 or 0.75)
        local dirty = self:IsDirty()
        if self.opts.external then
            self.Save:SetEnabled(editable)
        else
            self.Save:SetEnabled(editable and dirty)
        end
        self.Revert:SetEnabled(dirty)
        if dirty and self.opts.external then
            self.Status:SetText("|cffff9933Draft:|r Select All, Ctrl+C, then paste into the Guild window")
        elseif dirty then
            self.Status:SetText("|cffff9933Unsaved changes|r")
        elseif self.justSaved then
            self.Status:SetText("|cff40ff40Saved|r")
        else
            self.Status:SetText("")
        end
        if self.onState then self:onState() end
    end

    -- Load from the server, unless the user is mid-edit.
    function c:Load(force)
        local current = self.getter() or ""
        if force or not self:IsDirty() then
            self.saved = current
            self.Box:SetText(current)
        else
            self.saved = current -- keep their edit; Revert loads the new text
        end
        self:UpdateState()
    end

    c.Box:HookScript("OnTextChanged", function(_, user)
        if user then c.justSaved = false end
        c:UpdateState()
    end)
    c.Revert:SetScript("OnClick", function()
        c.justSaved = false
        c:Load(true)
    end)
    if opts.external then
        -- Opens Blizzard's Guild window, where the text can be pasted and saved.
        c.Save:SetText("Open Guild Window")
        c.Save:SetWidth(140)
        c.SelectAll = W.Button(c, "Select All", 90, 22)
        c.SelectAll:SetPoint("RIGHT", c.Revert, "LEFT", -6, 0)
        c.SelectAll:SetScript("OnClick", function()
            c.Box:SetFocus()
            c.Box:HighlightText()
        end)
        W.Tooltip(c.SelectAll, "Copy your draft", "Selects the text; press Ctrl+C to copy, then paste it into the Guild window's editor with Ctrl+V.")
        W.Tooltip(c.Save, "Open the Guild window",
            "The game only lets its own Guild window save guild information.",
            "Open its Info tab, click Edit next to Guild Information, paste your draft and click Accept.")
        local button = ns.GuildText:GuildButtonName()
        c.Save:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                ns:Print("The Guild window can't be opened by an addon during combat. Press your Guild key (J) instead.")
            elseif ToggleGuildFrame then
                ToggleGuildFrame()
            end
        end)
        if button then W.SecureOverlay(c.Save, { click = button }) end
    else
        -- Saving goes through a secure slash command (the direct function is
        -- restricted to Blizzard's UI). This plain handler only runs in combat.
        c.Save:SetScript("OnClick", function()
            ns:Print("You can't save this during combat.")
        end)
        W.SecureOverlay(c.Save, {
            macro = function()
                if not c.canEdit() or not c:IsDirty() then return nil end
                local line, clean = opts.command(c.Box:GetText() or "")
                if not line then return nil end
                c.pendingSave = clean
                return line
            end,
            post = function()
                if c.pendingSave then
                    c.saved = c.pendingSave
                    c.Box:SetText(c.pendingSave)
                    c.pendingSave = nil
                    c.justSaved = true
                    c.Box:ClearFocus()
                    ns.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
                end
                c:UpdateState()
            end,
        })
    end
    return c
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function IV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame
    local GT = ns.GuildText

    -- Toolbar
    self.guildName = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.guildName:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -36)
    self.guildSub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.guildSub:SetPoint("LEFT", self.guildName, "RIGHT", 12, -1)

    local options = W.Button(page, "Options", 90, 22)
    options:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    options:SetScript("OnClick", function() ns.Options:Open() end)
    W.Tooltip(options, "Addon options", "Icon, window title, minimap button and the Guild & Communities shortcut.")
    self.optionsButton = options

    local refresh = W.Button(page, "Refresh", 80, 22)
    refresh:SetPoint("RIGHT", options, "LEFT", -6, 0)
    refresh:SetScript("OnClick", function()
        ns.Roster:Request()
        GT:QueryNews()
        IV:Refresh(true)
    end)

    local inset = frame.Inset

    -- Message of the day
    local motd = TextCard(page, "Message of the Day", GT.MOTD_MAX,
        function() return GT:GetMOTD() end,
        function() return GT:CanEditMOTD() end,
        { command = function(text) return GT:MotdCommand(text) end })
    motd:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
    motd:SetHeight(170)
    motd.Editor:SetPoint("BOTTOMRIGHT", -16, 66)
    motd.Preview = motd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    motd.Preview:SetPoint("BOTTOMLEFT", 16, 42)
    motd.Preview:SetPoint("RIGHT", -16, 0)
    motd.Preview:SetJustifyH("LEFT")
    motd.Preview:SetWordWrap(false)
    motd.onState = function(c)
        local text = c.Box:GetText() or ""
        if text == "" then text = "(none)" end
        local line = GUILD_MOTD_TEMPLATE and GUILD_MOTD_TEMPLATE:format(text) or ("Guild Message of the Day: " .. text)
        c.Preview:SetText("|cff9d9d9dIn chat:|r |cff40ff40" .. line .. "|r")
    end
    -- The MOTD is a single line: drop line breaks as they're typed, Enter saves.
    motd.Box:HookScript("OnTextChanged", function(self, user)
        local text = self:GetText() or ""
        if user and text:find("[\r\n]") then self:SetText((text:gsub("[\r\n]+", " "))) end
    end)
    -- Enter finishes editing (saving needs a real click on Save: the game only
    -- runs protected actions from clicks).
    motd.Box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.motd = motd

    -- Guild information
    local info = TextCard(page, "Guild Information", GT.INFO_MAX,
        function() return GT:GetInfo() end,
        function() return GT:CanEditInfo() end,
        { external = true })
    info:SetPoint("TOPLEFT", motd, "BOTTOMLEFT", 0, -8)
    info:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 6)
    self.info = info

    -- Guild news
    local news = Card(page, "Guild News")
    news:SetPoint("TOPLEFT", motd, "TOPRIGHT", 8, 0)
    news:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
    news.Line:SetPoint("RIGHT", news, "RIGHT", -86, 0)
    news.Filters = W.Button(news, "Filters", 70, 20)
    news.Filters:SetPoint("TOPRIGHT", -10, -6)
    news.Filters:SetScript("OnClick", function(btn) IV:ShowFilterMenu(btn) end)

    local scrollBox = CreateFrame("Frame", nil, news, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 12, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -28, 12)
    local scrollBar = CreateFrame("EventFrame", nil, news, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(NEWS_ROW_H)
    view:SetElementInitializer("Button", function(row, item) IV:InitNewsRow(row, item) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    news.ScrollBox = scrollBox
    news.Empty = news:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    news.Empty:SetPoint("CENTER", scrollBox, "CENTER")
    news.Empty:SetWidth(240)
    self.news = news

    page:SetScript("OnShow", function()
        IV:OnResize()
        GT:QueryNews()
        IV:Refresh(true)
    end)
    ns:On("GUILD_TEXT_UPDATED", function() if page:IsVisible() then IV:Refresh() end end)
end

-- Text column takes 55% of the width.
function IV:OnResize()
    if not self.motd then return end
    local w = self.frame:GetWidth() - 10 - 12 - 8
    self.motd:SetWidth(math.floor(w * 0.55))
    self.info:SetWidth(math.floor(w * 0.55))
end

------------------------------------------------------------------------
-- News rows
------------------------------------------------------------------------
function IV:InitNewsRow(row, item)
    if not row.built then
        row.built = true
        row:SetHeight(NEWS_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:GetHighlightTexture():SetAlpha(0.3)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(13, 11)
        row.Icon:SetPoint("LEFT", 6, 0)
        row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", 24, 0)
        row.Text:SetPoint("RIGHT", -4, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetWordWrap(false)
        row.HeaderLine = row:CreateTexture(nil, "ARTWORK")
        row.HeaderLine:SetHeight(1)
        row.HeaderLine:SetPoint("BOTTOMLEFT", 4, 2)
        row.HeaderLine:SetPoint("BOTTOMRIGHT", -4, 2)
        row.HeaderLine:SetColorTexture(1, 0.82, 0, 0.25)
        row:SetScript("OnEnter", function(self)
            local it = self.item
            if not it or it.header then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if it.link and GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) then
                -- item tooltip shown
            else
                GameTooltip:AddLine(it.text, 1, 1, 1, true)
            end
            if ns.GuildText:CanSticky() then
                GameTooltip:AddLine(it.sticky and "Right-click to unpin" or "Right-click to pin to the top", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self, button)
            local it = self.item
            if button == "RightButton" and it and not it.header and ns.GuildText:CanSticky() then
                W.ShowMenu(self, {
                    { text = "Guild News", isTitle = true },
                    { text = it.sticky and "Unpin" or "Pin to top", func = function()
                        ns.GuildText:SetSticky(it.index, not it.sticky)
                        ns.GuildText:QueryNews()
                    end },
                })
            end
        end)
    end
    row.item = item
    if item.header then
        row.Icon:Hide()
        row.Text:SetPoint("LEFT", 6, 0)
        row.Text:SetFontObject("GameFontNormalSmall")
        row.Text:SetText(item.header)
        row.HeaderLine:Show()
    else
        row.Text:SetPoint("LEFT", 24, 0)
        row.Text:SetFontObject("GameFontHighlightSmall")
        row.Text:SetText(item.text)
        row.HeaderLine:Hide()
        if item.sticky then
            row.Icon:SetTexture("Interface\\GuildFrame\\GuildFrame")
            row.Icon:SetTexCoord(0.41406250, 0.42675781, 0.96875000, 0.99023438)
            row.Icon:Show()
        else
            row.Icon:Hide()
        end
    end
end

function IV:ShowFilterMenu(owner)
    local filters = ns.GuildText:Filters()
    local items = { { text = "Show in news", isTitle = true } }
    for _, f in ipairs(filters) do
        items[#items + 1] = {
            text = f.label,
            checked = function()
                for _, cur in ipairs(ns.GuildText:Filters()) do
                    if cur.id == f.id then return cur.on end
                end
            end,
            func = function()
                local on
                for _, cur in ipairs(ns.GuildText:Filters()) do
                    if cur.id == f.id then on = cur.on end
                end
                ns.GuildText:SetFilter(f.id, not on)
            end,
        }
    end
    if #filters == 0 then items[2] = { text = "No filters on this client", disabled = true } end
    W.ShowMenu(owner, items)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function IV:Refresh(force)
    if not self.page or not self.page:IsVisible() then return end
    local GT = ns.GuildText

    if IsInGuild() then
        self.guildName:SetText(GetGuildInfo("player") or "Guild")
        local total, online = ns.Roster:Stats()
        local _, rankName = GetGuildInfo("player")
        self.guildSub:SetText(("%d members  ·  |cff40ff40%d online|r%s"):format(total, online,
            rankName and ("  ·  your rank: " .. rankName) or ""))
    else
        self.guildName:SetText("Not in a guild")
        self.guildSub:SetText("")
    end

    self.motd:Load(force)
    self.info:Load(force)

    local news = self.news
    local list = GT:News()
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    news.ScrollBox:SetDataProvider(CreateDataProvider(list), retain)
    news.Filters:SetEnabled(#GT:Filters() > 0)
    if not GT:HasNews() then
        news.Empty:SetText("Guild news isn't available on this game client.")
    elseif #list == 0 then
        news.Empty:SetText("No guild news yet.")
    else
        news.Empty:SetText("")
    end
end
