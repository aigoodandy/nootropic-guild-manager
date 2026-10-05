--[[
    Nootropic Guild Manager - Goal page and goal form (on the Insights tab)
    Shown in the Insights tab's right-hand panel when a goal is picked from the
    list (UI/PollsView.lua keeps the list and decides what's shown):
      page   title, target date, a big bar (members matching / target), a bar
             for each part, who counts, and who's almost there (level goals)
      form   title, filters (with Add Filter), target, target date, parts,
             who can see it
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local GV = {}
ns.GoalsView = GV

local MAX_NAMES = 40
local BAR_H, PART_BAR_H, PART_H = 26, 20, 36

-- the character panel's skill bar look (UI/Widgets.lua)
local function Bar(parent, height) return W.StatBar(parent, height) end

-- "Asper, Marc, Shamandy" in class colors (and "and 3 more").
local function NameList(members, withLevel)
    local parts = {}
    for i = 1, math.min(MAX_NAMES, #members) do
        local e = members[i]
        parts[i] = ("|c%s%s|r"):format(ns.ClassHex(e.classFile), e.short) .. (withLevel and (" |cff9d9d9d" .. e.level .. "|r") or "")
    end
    local text = table.concat(parts, ", ")
    if #members > MAX_NAMES then text = text .. (" and %d more"):format(#members - MAX_NAMES) end
    return text
end

local function DueText(due)
    if not due then return "no target date" end
    local days = math.floor((due - ns.DB:Now()) / 86400 + 0.5)
    local when = date("%a %b %d", due)
    if days > 1 then return ("target %s (in %d days)"):format(when, days) end
    if days == 1 then return ("target %s (tomorrow)"):format(when) end
    if days == 0 then return ("target %s (today)"):format(when) end
    return ("target %s |cffff6060(%d days ago)|r"):format(when, -days)
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
function GV:Build(panel)
    local PV = ns.PollsView
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    p:Hide()
    self.page = p

    local title, line = W.SectionHeader(p, "Guild Goal")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    self.header = title

    self.title = PV.Para(p, "GameFontHighlight")
    self.title:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    self.title:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.status = PV.Para(p, "GameFontHighlightSmall")
    self.status:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
    self.status:SetPoint("RIGHT", p, "RIGHT", -14, 0)

    -- the main bar
    self.mainLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.mainLabel:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -14)
    self.mainLabel:SetPoint("RIGHT", p, "RIGHT", -120, 0)
    self.mainLabel:SetJustifyH("LEFT")
    self.mainLabel:SetWordWrap(false)
    self.mainCount = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.mainCount:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.mainCount:SetPoint("TOP", self.mainLabel, "TOP", 0, 0)
    self.mainBar = Bar(p, BAR_H)
    self.mainBar:SetPoint("TOPLEFT", self.mainLabel, "BOTTOMLEFT", 0, -4)
    self.mainBar:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.mainNote = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.mainNote:SetPoint("TOPLEFT", self.mainBar, "BOTTOMLEFT", 0, -4)

    -- parts
    self.partRows = {}
    for i = 1, ns.Goals.MAX_PARTS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(PART_H)
        r:SetPoint("TOPLEFT", self.mainNote, "BOTTOMLEFT", 0, -10 - (i - 1) * (PART_H + 4))
        r:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Label:SetPoint("TOPLEFT", 2, -2)
        r.Count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Count:SetPoint("TOPRIGHT", -2, -2)
        r.BarBg = Bar(r, PART_BAR_H)
        r.BarBg:SetPoint("BOTTOMLEFT", 0, 1)
        r.BarBg:SetPoint("BOTTOMRIGHT", 0, 1)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.filter then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.Label:GetText())
            GameTooltip:AddLine("Counted among the goal's members with: " .. self.filter, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.partRows[i] = r
    end

    -- who counts, who's almost there
    self.whoLabel = PV.Label(p, "Who counts")
    self.who = PV.Para(p, "GameFontHighlightSmall")
    self.who:SetPoint("TOPLEFT", self.whoLabel, "BOTTOMLEFT", 0, -4)
    self.who:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    self.almostLabel = PV.Label(p, "")
    self.almostLabel:SetPoint("TOPLEFT", self.who, "BOTTOMLEFT", 0, -10)
    self.almost = PV.Para(p, "GameFontHighlightSmall")
    self.almost:SetPoint("TOPLEFT", self.almostLabel, "BOTTOMLEFT", 0, -4)
    self.almost:SetPoint("RIGHT", p, "RIGHT", -14, 0)

    local edit = W.Button(p, "Edit Goal", 100, 22)
    edit:SetPoint("BOTTOMLEFT", 12, 12)
    edit:SetScript("OnClick", function() if GV.goal then GV:ShowEditor(GV.goal) end end)
    local del = W.Button(p, DELETE or "Delete", 90, 22)
    del:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    del:SetScript("OnClick", function()
        local g = GV.goal
        if not g then return end
        local who = g.vis == "m" and "" or (g.vis == "c" and " for everyone" or " for all officers")
        W.Confirm(("Delete the goal \"%s\"%s?"):format(g.title, who), function()
            local ok, err = ns.Goals:Delete(g.id)
            if not ok and err then
                ns:Print("|cffff5555" .. err .. "|r")
            else
                PV.selected = nil
                PV:Refresh()
            end
        end)
    end)
    self.editBtn, self.deleteBtn = edit, del

    self:BuildEditor(panel)
end

-- Shows a goal's page. Bars go in PollsView's list so they grow in with the rest.
function GV:ShowGoal(id)
    local PV = ns.PollsView
    local pr = ns.Goals:Progress(id)
    if not pr then return false end
    local g = pr.goal
    self.goal = g
    self.header:SetText(g.vis == "o" and "Officer Goal" or g.vis == "m" and "My Goal" or "Guild Goal")
    self.title:SetText(g.title)
    self.status:SetText("|cff66bbffLive  -  " .. DueText(g.due) .. "|r" ..
        ((g.filter or "") ~= "" and ("  |cff9d9d9dFilters: " .. g.filter .. "|r") or ""))

    -- main bar: gold, green once reached
    self.mainLabel:SetText("Members")
    self.mainCount:SetText(("|cffffffff%d|r / %d  |cff9d9d9d%d%%|r"):format(pr.count, pr.target, pr.pct))
    local bar = self.mainBar.Bar
    if pr.done then bar:SetStatusBarColor(0.2, 0.8, 0.3) else bar:SetStatusBarColor(1, 0.75, 0.1) end
    PV.barTargets[bar] = math.min(1, pr.count / math.max(1, pr.target))
    bar:SetValue(PV.barTargets[bar])
    local left = pr.target - pr.count
    self.mainNote:SetText(pr.done and "|cff40ff40Goal reached!|r" or (left == 1 and "1 more to go." or (left .. " more to go.")))

    -- parts
    local last = self.mainNote
    for i, r in ipairs(self.partRows) do
        local part = pr.parts[i]
        if part then
            r.filter = part.filter
            r.Label:SetText(part.label)
            r.Count:SetText(("|cffffffff%d|r / %d"):format(part.count, part.need) .. (part.done and "  |cff40ff40done|r" or ""))
            local pb = r.BarBg.Bar
            local color = part.done and { 0.2, 0.8, 0.3 } or { D:TagColor(D:NextColor(i)) }
            pb:SetStatusBarColor(color[1], color[2], color[3])
            PV.barTargets[pb] = math.min(1, part.count / math.max(1, part.need))
            pb:SetValue(PV.barTargets[pb])
            r:Show()
            last = r
        else
            r:Hide()
        end
    end

    self.whoLabel:ClearAllPoints()
    self.whoLabel:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -14)
    self.who:SetText(#pr.members > 0 and NameList(pr.members) or "|cff9d9d9dNobody yet.|r")
    if pr.almost then
        self.almostLabel:SetText(("Almost there  |cff9d9d9d(level %d+)|r"):format(pr.almostFrom))
        self.almost:SetText(#pr.almost > 0 and NameList(pr.almost, true) or "|cff9d9d9dNobody close yet.|r")
        self.almostLabel:Show()
        self.almost:Show()
    else
        self.almostLabel:Hide()
        self.almost:Hide()
    end

    local editable = ns.Goals:CanEdit(g)
    self.editBtn:SetShown(editable)
    self.deleteBtn:SetShown(editable)
    return true
end

------------------------------------------------------------------------
-- Form
------------------------------------------------------------------------
function GV:BuildEditor(panel)
    local PV, GL = ns.PollsView, ns.Goals
    local IW = 312
    local c = CreateFrame("Frame", nil, panel)
    c:SetAllPoints()
    c:Hide()
    self.form = c

    local title, line = W.SectionHeader(c, "New Goal")
    title:SetPoint("TOPLEFT", 14, -12)
    line:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    self.fHeader = title

    local tLabel = PV.Label(c, "Title")
    tLabel:SetPoint("TOPLEFT", 14, -36)
    self.fTitle = PV.Input(c, IW - 8, GL.TITLE_MAX)
    self.fTitle:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 6, -2)

    local fLabel = PV.Label(c, "Who counts  |cff9d9d9d(filters, like a stat's)|r")
    fLabel:SetPoint("TOPLEFT", 14, -80)
    self.fFilter = PV.Input(c, IW - 8, GL.FILTER_MAX)
    self.fFilter:SetPoint("TOPLEFT", fLabel, "BOTTOMLEFT", 6, -2)
    self.fFilter:HookScript("OnTextChanged", function(_, user) if user then GV:RefreshEditor() end end)
    W.Tooltip(self.fFilter, "Who counts", "The same words as the roster search; every one must match.",
        "level>=60  is:main  class:warrior  role:tank  rank:raider  tag:raiding  prof:alchemy")
    local add = W.Button(c, "Add Filter", 100, 20)
    add:SetPoint("TOPLEFT", self.fFilter, "BOTTOMLEFT", -6, -4)
    add:SetScript("OnClick", function(btn) PV:FilterMenu(btn, GV.fFilter, function() GV:RefreshEditor() end) end)
    local clear = W.Button(c, "Clear", 70, 20)
    clear:SetPoint("LEFT", add, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function()
        GV.fFilter:SetText("")
        GV:RefreshEditor()
    end)
    self.fMatches = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.fMatches:SetPoint("LEFT", clear, "RIGHT", 10, 0)

    -- target and date on one line
    local targetLabel = PV.Label(c, "Target")
    targetLabel:SetPoint("TOPLEFT", 14, -156)
    self.fTarget = PV.Input(c, 40, 3, true)
    self.fTarget:SetPoint("LEFT", targetLabel, "RIGHT", 10, 0)
    local members = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    members:SetPoint("LEFT", self.fTarget, "RIGHT", 6, 0)
    members:SetText("members")
    local dueLabel = PV.Label(c, "Target date in")
    dueLabel:SetPoint("LEFT", members, "RIGHT", 18, 0)
    self.fDays = PV.Input(c, 36, 3, true)
    self.fDays:SetPoint("LEFT", dueLabel, "RIGHT", 10, 0)
    self.fDays:HookScript("OnTextChanged", function() GV:RefreshEditor() end)
    local days = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    days:SetPoint("LEFT", self.fDays, "RIGHT", 6, 0)
    days:SetText("days")
    self.fDue = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.fDue:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -8)
    W.Tooltip(self.fDays, "Target date (optional)", "How many days from today. Leave empty for no date.")

    -- parts: name, filter, how many
    local pLabel = PV.Label(c, "Parts  |cff9d9d9d(optional: smaller targets among them)|r")
    pLabel:SetPoint("TOPLEFT", 14, -196)
    self.fParts = {}
    for i = 1, GL.MAX_PARTS do
        local y = -214 - (i - 1) * 24
        local name = PV.Input(c, 80, 24)
        name:SetPoint("TOPLEFT", 20, y)
        local filter = PV.Input(c, 130, GL.FILTER_MAX)
        filter:SetPoint("LEFT", name, "RIGHT", 10, 0)
        local plus = W.Button(c, "+", 22, 20)
        plus:SetPoint("LEFT", filter, "RIGHT", 2, 0)
        plus:SetScript("OnClick", function(btn) PV:FilterMenu(btn, filter, function() end) end)
        W.Tooltip(plus, "Add a filter", "Pick what this part counts, like Role > Tank.")
        local need = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        need:SetPoint("LEFT", plus, "RIGHT", 8, 0)
        need:SetText("need")
        local count = PV.Input(c, 30, 3, true)
        count:SetPoint("LEFT", need, "RIGHT", 8, 0)
        W.Tooltip(name, "Part name", "For example: Tanks")
        W.Tooltip(filter, "Part filter", "Who counts for this part, among the goal's members. For example: role:tank")
        self.fParts[i] = { name = name, filter = filter, need = count }
    end

    local vLabel = PV.Label(c, "Who can see it")
    vLabel:SetPoint("TOPLEFT", 14, -214 - GL.MAX_PARTS * 24 - 8)
    local vis = PV.DropButton(c, 170)
    vis:SetPoint("LEFT", vLabel, "RIGHT", 10, 0)
    vis:SetScript("OnClick", function(btn)
        local officer = ns.IsOfficer()
        local items = { { text = "Who can see it", isTitle = true } }
        for _, v in ipairs(ns.Stats.VISIBILITY) do
            items[#items + 1] = { text = v.label, radio = true,
                disabled = v.key ~= "m" and not officer,
                checked = function() return GV.fVis == v.key end,
                func = function()
                    if v.key ~= "m" and not ns.IsOfficer() then return end
                    GV.fVis = v.key
                    GV:RefreshEditor()
                end }
        end
        W.ShowMenu(btn, items)
    end)
    self.fVisBtn = vis

    local save = W.Button(c, SAVE or "Save", 100, 22)
    save:SetPoint("BOTTOMLEFT", 12, 12)
    save:SetScript("OnClick", function() GV:Save() end)
    local cancel = W.Button(c, CANCEL or "Cancel", 90, 22)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        PV.mode = nil
        PV:Refresh()
    end)
    self.fError = PV.Para(c, "GameFontHighlightSmall", IW)
    self.fError:SetPoint("BOTTOMLEFT", save, "TOPLEFT", 2, 8)
    self.fError:SetTextColor(1, 0.35, 0.35)

    -- tab moves through the boxes
    local order = { self.fTitle, self.fFilter, self.fTarget, self.fDays }
    for _, part in ipairs(self.fParts) do
        order[#order + 1] = part.name
        order[#order + 1] = part.filter
        order[#order + 1] = part.need
    end
    for i, box in ipairs(order) do box.nextBox = order[i + 1] or order[1] end
end

-- goal: the goal to edit, or nil for a new one.
function GV:ShowEditor(goal)
    local PV = ns.PollsView
    if not ns.DB:Guild() then return end
    PV.mode = "goalForm"
    self.editing = goal and goal.id or nil
    self.fHeader:SetText(goal and "Edit Goal" or "New Goal")
    self.fTitle:SetText(goal and goal.title or "")
    self.fFilter:SetText(goal and goal.filter or "")
    self.fTarget:SetText(goal and tostring(goal.target) or "10")
    local days = goal and goal.due and math.max(0, math.floor((goal.due - ns.DB:Now()) / 86400 + 0.5))
    self.fDays:SetText(days and tostring(days) or "")
    for i, row in ipairs(self.fParts) do
        local part = goal and goal.parts[i]
        row.name:SetText(part and part.label or "")
        row.filter:SetText(part and part.filter or "")
        row.need:SetText(part and tostring(part.need) or "")
    end
    self.fVis = goal and goal.vis or (ns.IsOfficer() and "c" or "m")
    self.fError:SetText("")
    PV:Refresh()
    self.fTitle:SetFocus()
end

function GV:RefreshEditor()
    local n, total = ns.Stats:MatchCount(self.fFilter:GetText())
    self.fMatches:SetText(("Matches %d of %d members"):format(n, total))
    local days = tonumber(self.fDays:GetText())
    self.fDue:SetText(days and ("Target date: " .. date("%a %b %d", ns.DB:Now() + days * 86400)) or "No target date.")
    if self.fVis ~= "m" and not ns.IsOfficer() then self.fVis = "m" end
    for _, v in ipairs(ns.Stats.VISIBILITY) do
        if v.key == self.fVis then self.fVisBtn:SetText(v.label) end
    end
    self.fError:SetText("")
end

function GV:Save()
    local parts = {}
    for _, row in ipairs(self.fParts) do
        parts[#parts + 1] = { label = row.name:GetText(), filter = row.filter:GetText(), need = row.need:GetText() }
    end
    local days = tonumber(self.fDays:GetText())
    local id, err = ns.Goals:Save(self.editing, {
        title = self.fTitle:GetText(), filter = self.fFilter:GetText(), target = self.fTarget:GetText(),
        due = days and (ns.DB:Now() + days * 86400) or nil, parts = parts, vis = self.fVis,
    })
    if not id then
        self.fError:SetText(err or "Couldn't save the goal.")
        return
    end
    self.fTitle:ClearFocus()
    ns.PollsView:Select("goal:" .. id)
end
