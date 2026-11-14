--[[
    Nootropic Guild Manager - Upcoming Events tab
    The guild's upcoming events from NGM Peon (Services/Events.lua), as the
    dashboard's Upcoming Events tab shows them: when (your own time), what,
    how long, how many are coming, and where to sign up (the Discord channel
    and server). Each in a box, as the dashboard's.
]]
local _, ns = ...
local W = ns.Widgets
local EV = {}
ns.EventsView = EV

local GRAY = "|cff9d9d9d"
local KIND = { dungeon = "Dungeon", raid = "Raid", event = "Event" }
local PAD, EDGE, GAP = 14, 4, 16

local function Card(parent)
    local T = ns.Theme
    local c = CreateFrame("Frame", nil, parent)
    T:Box(c, T.C.bg1, T.C.edge, EDGE)
    c.Title = c:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    c.Title:SetPoint("TOPLEFT", PAD, -PAD)
    c.Title:SetPoint("RIGHT", -140, 0)
    c.Title:SetJustifyH("LEFT")
    c.Title:SetWordWrap(false)
    c.Coming = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Coming:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
    c.Coming:SetJustifyH("RIGHT")
    c.When = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.When:SetPoint("TOPLEFT", c.Title, "BOTTOMLEFT", 0, -6)
    c.When:SetJustifyH("LEFT")
    c.Text = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Text:SetPoint("TOPLEFT", c.When, "BOTTOMLEFT", 0, -6)
    c.Text:SetJustifyH("LEFT")
    c.Where = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.Where:SetJustifyH("LEFT")
    return c
end

function EV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)

    local inset = frame.Inset
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMEventsScroll", page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    self.content = content
    self.cards = {}
    self.empty = content:CreateFontString(nil, "OVERLAY", "NGMFontDim")
    self.empty:SetPoint("TOPLEFT", EDGE, -EDGE)
    self.empty:SetJustifyH("LEFT")
    self.note = content:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.note:SetJustifyH("LEFT")

    page:SetScript("OnShow", function() EV:Refresh() end)
    page:SetScript("OnSizeChanged", function() if page:IsVisible() then EV:Refresh() end end)
end

function EV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local list = ns.Events:List()
    self.title:SetText(("Upcoming Events  " .. GRAY .. "- %d in the next 30 days|r"):format(#list))
    local width = math.max(300, math.floor(self.scroll:GetWidth()))
    local inner = width - 2 * EDGE
    local y = EDGE
    self.empty:SetShown(#list == 0)
    self.empty:SetWidth(inner)
    self.empty:SetText("No upcoming events yet. Events are created on the " .. ns.GOLD .. "NGM Peon dashboard|r (Create Events tab), and reach the game when an officer brings in NGM Peon's code (" .. ns.GOLD .. "/ngm peon|r).")
    for i, ev in ipairs(list) do
        local c = self.cards[i] or Card(self.content)
        self.cards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", EDGE, -y)
        c:SetWidth(inner)
        c.Title:SetText(ns.Theme.Upper(ev.title ~= "" and ev.title or "Event"))
        c.Coming:SetText(("%d coming"):format(ev.coming or 0))
        local length = ev.minutes >= 60 and ((ev.minutes / 60) .. " h") or (ev.minutes .. " min")
        c.When:SetText(("%s  " .. GRAY .. "·|r  %s  " .. GRAY .. "·|r  %s"):format(date("%a %d %b, %H:%M", ev.starts), KIND[ev.kind] or "Event", length))
        c.Text:SetWidth(inner - 2 * PAD)
        c.Text:SetText(ev.description or "")
        c.Text:SetShown((ev.description or "") ~= "")
        c.Where:ClearAllPoints()
        c.Where:SetPoint("TOPLEFT", c.Text:IsShown() and c.Text or c.When, "BOTTOMLEFT", 0, -8)
        c.Where:SetWidth(inner - 2 * PAD)
        -- sign-ups are in Discord only: one list per event
        local where = ev.channel ~= "" and (" " .. GRAY .. "·|r #" .. ev.channel) or ""
        local server = ev.server ~= "" and (" " .. GRAY .. "on|r " .. ev.server) or ""
        c.Where:SetText(ns.GOLD .. "Sign up in Discord|r" .. where .. server)
        local h = PAD + c.Title:GetStringHeight() + 6 + c.When:GetStringHeight()
            + (c.Text:IsShown() and (6 + c.Text:GetStringHeight()) or 0) + 8 + c.Where:GetStringHeight() + PAD
        c:SetHeight(h)
        c:Show()
        y = y + h + GAP
    end
    for i = #list + 1, #self.cards do self.cards[i]:Hide() end
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", EDGE, -(#list == 0 and (EDGE + 30) or y))
    self.note:SetWidth(inner)
    self.note:SetText("Times are your own. Sign up in Discord, with the buttons on each event's post. New events are created on the " .. ns.GOLD .. "NGM Peon dashboard|r (Create Events tab).")
    self.content:SetSize(width, y + 40)
end
