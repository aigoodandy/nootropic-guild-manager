--[[
    Nootropic Guild Manager - Mini recruiter
    A small bar for recruiting while you play: status and countdown, Search
    /who, Select New and Send / Stop / Send Next. Open it with the Compact button on the
    Recruitment tab (or /ngm mini); it also appears when the main window is
    closed while whispers are still being sent. Expand goes back to the tab.
    Its position is saved (settings.miniPos).
]]
local _, ns = ...
local W = ns.Widgets
local MR = {}
ns.RecruitMini = MR

local WIDTH, HEIGHT = 320, 82

function MR:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "NootropicGMRecruitMini", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.DB:Settings().miniPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:Hide()
    self.frame = f

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 10, -9)
    W.SetIcon(icon, "Interface\\Icons\\INV_Letter_15")

    local title = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Recruiting")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() MR:Hide() end)
    W.Tooltip(close, "Hide", "Whispers already queued keep sending. /ngm mini brings the bar back.")

    local expand = W.SizeButton(f, "expand", 26, function() MR:Expand() end,
        "Expand", "Back to the full Recruitment tab.")
    expand:SetPoint("RIGHT", close, "LEFT", 0, 0)
    expand:MatchLevel(close)

    self.status = f:CreateFontString(nil, "OVERLAY", "NootropicGM_GameFontHighlightSmall")
    self.status:SetPoint("TOPLEFT", 12, -30)
    self.status:SetPoint("RIGHT", -12, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)

    local search = W.Button(f, "Search /who", 100, 22)
    search:SetPoint("BOTTOMLEFT", 10, 10)
    -- /who runs through a secure button, like on the Recruitment tab
    search:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            ns:Print("You can't search while in combat.")
            return
        end
        local ok, err = ns.Recruit:Search()
        if not ok and err then ns:Print("|cffff5555" .. err .. "|r") end
        MR:Refresh()
    end)
    W.SecureOverlay(search, {
        macro = function() return ns.Recruit:WhoMacro() end,
        post = function() MR:Refresh() end,
    })
    search:SetScript("OnEnter", function(self)
        local r = ns.Recruit:Settings()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Search /who")
        if r then
            GameTooltip:AddLine("Searches: " .. ns.Recruit:BuildQuery(r.query), 1, 1, 1, true)
            if r.query.step then GameTooltip:AddLine("Step levels is on: each search moves to the next level range.", 0.7, 0.7, 0.7, true) end
        end
        GameTooltip:AddLine("Change the filters on the Recruitment tab (Expand).", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.searchBtn = search

    local selNew = W.Button(f, "Select New", 92, 22)
    selNew:SetPoint("LEFT", search, "RIGHT", 4, 0)
    selNew:SetScript("OnClick", function()
        ns.Recruit:SelectNew(ns.Recruit:List({ name = MR:NameFilter() }))
        MR:Refresh()
    end)
    W.Tooltip(selNew, "Select new players", "Ticks everyone found who nobody in the guild has whispered yet.")
    self.selNewBtn = selNew

    local send = W.Button(f, "Send", 100, 22)
    send:SetPoint("LEFT", selNew, "RIGHT", 4, 0)
    send:SetPoint("RIGHT", -10, 0)
    send:SetScript("OnClick", function()
        ns.RecruitView:OnSendClicked(ns.Recruit:List())
        MR:Refresh()
    end)
    self.sendBtn = send

    -- countdowns tick while the bar is open
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.5 then return end
        elapsed = 0
        MR:Refresh()
    end)
    ns:On("RECRUITS_CHANGED", function() if f:IsShown() then MR:Refresh() end end)
    return f
end

function MR:RestorePosition()
    local f, pos = self.frame, ns.DB:Settings().miniPos
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- The Recruitment tab's Name filter (the bar shows the same players).
function MR:NameFilter()
    local r = ns.Recruit:Settings()
    return r and r.query.name or ""
end

-- One line: what's happening right now.
function MR:StatusText()
    local RC = ns.Recruit
    local r = RC:Settings()
    if not r then return "|cff9d9d9dJoin a guild to recruit.|r" end
    if RC.searching then return "|cffffd100Searching:|r " .. (RC.pendingQuery or "") end
    local _, _, info = ns.RecruitView:SendState()
    if RC:IsSending() then return "|cffffd100" .. info .. "|r" end
    local selected = RC:SelectedCount()
    if selected > 0 then return ("|cff40ff40%d ticked|r - click Send"):format(selected) end
    local last = RC.last
    if last and last.timedOut then return "|cffff8080No reply from /who - wait a few seconds.|r" end
    local ready = 0
    for _, p in ipairs(RC:List({ hideContacted = true, name = self:NameFilter() })) do
        if RC:CanSelect(p) then ready = ready + 1 end
    end
    local found = last and not last.timedOut and ("Last search: |cff40ff40%d new|r.  "):format(last.new or 0) or ""
    return found .. (ready == 1 and "1 player ready to whisper" or (ready .. " players ready to whisper"))
end

function MR:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local RC = ns.Recruit
    self.status:SetText(self:StatusText())
    local searchText, searchOn = ns.RecruitView:SearchState()
    self.searchBtn:SetText(searchText)
    self.searchBtn:SetEnabled(searchOn)
    local sendText, sendOn = ns.RecruitView:SendState(true)
    self.sendBtn:SetText(sendText)
    self.sendBtn:SetEnabled(sendOn)
    self.selNewBtn:SetEnabled(not RC:IsSending() and RC:Settings() ~= nil)
end

function MR:Show()
    local f = self:Build()
    if not f:IsShown() then self:RestorePosition() end
    f:Show()
    self:Refresh()
end

function MR:Hide()
    if self.frame then self.frame:Hide() end
end

function MR:IsShown()
    return self.frame and self.frame:IsShown() or false
end

function MR:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

-- From the Recruitment tab: close the big window, show the bar.
function MR:Compact()
    self:Show()
    ns.UI:Hide()
end

-- Back to the full Recruitment tab.
function MR:Expand()
    self:Hide()
    ns.UI:Show()
    ns.UI:SelectTab(ns.UI.TAB_RECRUIT)
end
