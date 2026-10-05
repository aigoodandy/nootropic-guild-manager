--[[
    Nootropic Guild Manager - Recruitment whisper buttons on the game's /who window
    Adds a small whisper button to each player row of the /who results (the
    "Looking For Group" people search, or the classic Who list). A click sends
    that player the recruitment whisper, exactly like the Recruitment tab:
    custom messages when they're on, the Do Not Whisper list, players the guild
    already contacted, and the paced whisper queue (Services/Recruit.lua).

    The window differs between clients, so nothing here depends on its frame
    names: after each /who search the addon looks for visible rows showing a
    player name from the results, then keeps watching those rows' parent
    (lists reuse rows while scrolling) while it's on screen.

    Option: settings.whoWhisperButton (on unless turned off in Options).
]]
local _, ns = ...
local W = ns.Widgets
local WI = {}
ns.WhoWhisper = WI

local SIZE = 26
local WHISPER_ICONS = { "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_01" }

WI.containers = {} -- row parents we watch -> true
WI.buttons = {}    -- row -> our button

function WI:Enabled()
    return ns.DB:Settings().whoWhisperButton ~= false
end

function WI:SetEnabled(on)
    ns.DB:Settings().whoWhisperButton = on and true or false
    if on then self:Scan() end
    self:UpdateAll()
    ns:Fire("SETTINGS_CHANGED")
end

------------------------------------------------------------------------
-- Current /who results, by lower-case name (with and without realm)
------------------------------------------------------------------------
local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function WI:Results()
    local out, n = {}, 0
    local count
    if C_FriendList and C_FriendList.GetNumWhoResults then
        count = C_FriendList.GetNumWhoResults()
    elseif GetNumWhoResults then
        count = GetNumWhoResults()
    end
    for i = 1, count or 0 do
        local name, guild, level, className, classFile, zone, race = ns.Recruit.ReadWho(i)
        if name and name ~= "" then
            local info = { name = name, guild = guild or "", level = level, className = className,
                classFile = classFile, zone = zone, race = race }
            out[name:lower()] = info
            out[ns.ShortName(name):lower()] = out[ns.ShortName(name):lower()] or info
            n = n + 1
        end
    end
    self.results, self.resultCount = out, n
    return out
end

-- Our own windows also list names (the recruit list); never touch them.
local function IsOurs(frame)
    local f, depth = frame, 0
    while f and depth < 20 do
        local name = f.GetName and f:GetName()
        if name and name:find("^NootropicGM") then return true end
        if f == GameTooltip then return true end
        f = f:GetParent()
        depth = depth + 1
    end
    return false
end

-- Visible text of a frame's own font strings, lower case, colors removed.
local function Texts(obj, out)
    for _, region in ipairs({ obj:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:IsShown() then
            local text = region:GetText()
            if text and text ~= "" then out[#out + 1] = ns.Trim(StripColors(text)):lower() end
        end
    end
    return out
end

local function NameIn(texts, results)
    for _, t in ipairs(texts) do
        if results[t] then return results[t] end
    end
end

-- The /who result a row shows, or nil. The name must be the row's own text
-- (deep: or a child's, for windows that nest it), and the row must also show
-- that player's zone or class, so a target frame or nameplate never counts.
local function RowInfo(row, results, deep)
    local own = Texts(row, {})
    local info = NameIn(own, results)
    local all = own
    for _, child in ipairs({ row:GetChildren() }) do
        if child ~= WI.buttons[row] then
            local ct = Texts(child, {})
            if not info and deep and child:GetObjectType() ~= "Button" then info = NameIn(ct, results) end
            for _, t in ipairs(ct) do all[#all + 1] = t end
        end
    end
    if not info then return nil end
    local zone, cls = (info.zone or ""):lower(), (info.className or ""):lower()
    for _, t in ipairs(all) do
        if (zone ~= "" and t:find(zone, 1, true)) or (cls ~= "" and t:find(cls, 1, true)) then return info end
    end
end

-- A frame holding several results is the list, not a row.
local function NamesInChildren(frame, results)
    local n = 0
    for _, child in ipairs({ frame:GetChildren() }) do
        if NameIn(Texts(child, {}), results) then n = n + 1 end
    end
    return n
end

------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------
-- The row's own rightmost button (e.g. invite to group), to sit beside it.
local function RightmostButton(row, mine)
    local best, bestRight
    for _, child in ipairs({ row:GetChildren() }) do
        if child ~= mine and child:IsShown() and child:GetObjectType() == "Button" then
            local right = child:GetRight()
            if right and (not bestRight or right > bestRight) then best, bestRight = child, right end
        end
    end
    return best
end

local function CreateButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(SIZE, SIZE)
    b:SetFrameLevel(row:GetFrameLevel() + 5)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints()
    for _, path in ipairs(WHISPER_ICONS) do
        if b.Icon:SetTexture(path) ~= false then break end
    end
    b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.Border = b:CreateTexture(nil, "OVERLAY")
    b.Border:SetPoint("TOPLEFT", -1, 1)
    b.Border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.Border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.Border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    b.Border:SetAlpha(0.6)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b.Check = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.Check:SetSize(16, 16)
    b.Check:SetPoint("BOTTOMRIGHT", 3, -3)
    b.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.Check:Hide()
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end -- tooltip says why it's off

    b.Wait = b:CreateFontString(nil, "OVERLAY", "NootropicGM_NumberFontNormalSmall")
    b.Wait:SetPoint("CENTER", 0, 0)
    b.Wait:SetText("...")
    b.Wait:Hide()

    b:SetScript("OnClick", function(self)
        local info = self.info
        if not info then return end
        local ok, err = ns.Recruit:WhisperFromWho(info)
        if ok then
            ns.PlaySound("U_CHAT_SCROLL_BUTTON")
            -- keep the countdown (and Send Next, on click-only clients) on screen
            if not (ns.UI.frame and ns.UI.frame:IsShown()) then ns.RecruitMini:Show() end
        elseif err then
            ns:Print("|cffff5555" .. err .. "|r")
        end
        WI:UpdateButton(row)
    end)
    b:SetScript("OnEnter", function(self)
        local info = self.info
        if not info then return end
        local RC = ns.Recruit
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Send recruitment whisper")
        GameTooltip:AddLine(ns.ShortName(info.name), ns.ClassColor(info.classFile))
        if self.state == "queued" then
            GameTooltip:AddLine("Waiting in the whisper queue (whispers are spaced out).", 1, 0.82, 0, true)
        elseif self.state == "sent" then
            GameTooltip:AddLine("Whispered.", 0.4, 1, 0.4, true)
        elseif self.reason then
            GameTooltip:AddLine(self.reason, 1, 0.5, 0.5, true)
        end
        if self.state == nil and not self.reason then
            -- the message they'd get, as on the Recruitment tab
            local p = { full = ns.NormalizeName(info.name), short = ns.ShortName(info.name), level = info.level,
                classFile = info.classFile, className = info.className, zone = info.zone, race = info.race,
                guild = info.guild ~= "" and info.guild or nil }
            local text, rule = RC:TemplateFor(p)
            local msg = RC:Format(text, p)
            GameTooltip:AddLine("Message: " .. (rule and rule.name or "Default"), 1, 0.82, 0)
            GameTooltip:AddLine(msg ~= "" and ("|cffff80ff" .. msg .. "|r") or "|cff9d9d9d(empty - write a message on the Recruitment tab)|r", 1, 1, 1, true)
            GameTooltip:AddLine("Click to whisper. Whispers are spaced out like on the Recruitment tab.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine("Nootropic Guild Manager - turn off in Options.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Shows, places and enables the row's button for the player it shows now.
function WI:UpdateButton(row)
    local b = self.buttons[row]
    local info = self:Enabled() and self.results and row:IsVisible() and RowInfo(row, self.results, self.deep)
    if not info then
        if b then b:Hide() end
        return
    end
    if not b then
        b = CreateButton(row)
        self.buttons[row] = b
    end
    b.info = info
    local anchor = RightmostButton(row, b)
    b:ClearAllPoints()
    if anchor then
        b:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        b:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    end
    -- queued, already whispered, or why it can't be used
    local RC = ns.Recruit
    local full = ns.NormalizeName(info.name)
    local r = RC:Settings()
    local p = r and full and r.people[full]
    local state
    if full and RC:IsQueued(full) then
        state = "queued"
    elseif p and p.whispered then
        state = "sent"
    end
    local reason = not state and full and RC:WhisperBlocked(full, p) or nil
    b.state, b.reason = state, reason
    b.Wait:SetShown(state == "queued")
    b:SetEnabled(state == nil and reason == nil)
    b.Icon:SetDesaturated(reason ~= nil or state == "queued")
    b.Icon:SetAlpha((reason or state == "queued") and 0.5 or 1)
    b.Check:SetShown(state == "sent")
    b:Show()
end

function WI:UpdateAll()
    for row in pairs(self.buttons) do self:UpdateButton(row) end
    for container in pairs(self.containers) do
        if container:IsVisible() then
            for _, row in ipairs({ container:GetChildren() }) do
                if row:IsVisible() and not self.buttons[row] then self:UpdateButton(row) end
            end
        end
    end
end

------------------------------------------------------------------------
-- Finding the rows
------------------------------------------------------------------------
-- Looks through every visible frame for rows showing a /who result: first
-- rows whose own text has the name, then (if none) rows that nest it.
function WI:Scan()
    if not self:Enabled() or not EnumerateFrames then return end
    local results = self:Results()
    if self.resultCount == 0 then return end
    local function Pass(deep)
        local found = 0
        local f = EnumerateFrames()
        local guard = 0
        while f and guard < 50000 do
            guard = guard + 1
            local frame = f
            local ok, isRow = pcall(function()
                if not (frame:IsVisible() and frame.GetRegions) or WI.buttons[frame] then return false end
                if not RowInfo(frame, results, deep) then return false end
                return not deep or NamesInChildren(frame, results) <= 1
            end)
            if ok and isRow and not IsOurs(frame) then
                found = found + 1
                local parent = frame:GetParent()
                if parent and parent ~= UIParent then self.containers[parent] = true end
                self:UpdateButton(frame)
            end
            f = EnumerateFrames(f)
        end
        return found
    end
    local found = Pass(self.deep)
    if found == 0 and not self.deep and not next(self.buttons) then
        self.deep = true
        found = Pass(true)
        if found == 0 then self.deep = false end
    end
    self.lastFound = found
    self:UpdateAll()
end

-- /ngm diag: what the whisper buttons can see.
function WI:Diagnose()
    local shown = 0
    for _, b in pairs(self.buttons) do if b:IsVisible() then shown = shown + 1 end end
    local containers = 0
    for _ in pairs(self.containers) do containers = containers + 1 end
    ns:Print(("/who whisper buttons: enabled=%s, results=%d, rows found last search=%s, lists=%d, buttons showing=%d%s"):format(
        tostring(self:Enabled()), self.resultCount or 0, tostring(self.lastFound or "none yet"), containers, shown,
        self.deep and ", nested rows" or ""))
    if (self.resultCount or 0) > 0 and (self.lastFound or 0) == 0 then
        ns:Print("  The /who window's rows weren't recognized. Search with the window open, then run /ngm diag again.")
    end
end

function WI:Init()
    local watcher = CreateFrame("Frame")
    -- the window fills its rows a moment after the results arrive
    ns:RegisterEvent("WHO_LIST_UPDATE", function()
        if not WI:Enabled() then return end
        WI:Results()
        for _, delay in ipairs({ 0.1, 0.6, 1.5 }) do
            C_Timer.After(delay, function() WI:Scan() end)
        end
    end)
    -- rows are reused while scrolling: keep the buttons matched to them
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.25 then return end
        elapsed = 0
        if not WI:Enabled() or not next(WI.buttons) then return end
        local any = false
        for container in pairs(WI.containers) do
            if container:IsVisible() then any = true break end
        end
        if any then WI:UpdateAll() end
    end)
    ns:On("ROSTER_UPDATED", function() if next(WI.buttons) then WI:UpdateAll() end end)
    ns:On("RECRUITS_CHANGED", function() if next(WI.buttons) then WI:UpdateAll() end end)
end
