--[[
    Nootropic Guild Manager - Guild text service
    Message of the day, guild information and guild news, wrapping the
    modern C_GuildInfo API with fallbacks for older clients. Uses the same
    calls as Blizzard's Guild & Communities window. Fires GUILD_TEXT_UPDATED.
]]
local _, ns = ...
local GT = {}
ns.GuildText = GT

-- The MOTD is saved by running "/gmotd <text>" (one chat line, 255 max).
GT.MOTD_MAX = 255 - #((SLASH_GUILD_MOTD1 or "/gmotd") .. " ")
GT.INFO_MAX = 499

------------------------------------------------------------------------
-- Message of the day
------------------------------------------------------------------------
function GT:GetMOTD()
    if C_GuildInfo and C_GuildInfo.GetMOTD then return C_GuildInfo.GetMOTD() or "" end
    if GetGuildRosterMOTD then return GetGuildRosterMOTD() or "" end
    return ""
end

function GT:CanEditMOTD()
    return IsInGuild() and CanEditMOTD ~= nil and CanEditMOTD() and true or false
end

-- Setting the MOTD is restricted to Blizzard's UI, so the Info tab's Save
-- button runs this slash command through a secure button instead.
function GT:MotdCommand(text)
    if not self:CanEditMOTD() then return nil, "Your guild rank can't change the message of the day." end
    text = (text or ""):gsub("[\r\n]+", " "):sub(1, self.MOTD_MAX)
    return (SLASH_GUILD_MOTD1 or "/gmotd") .. " " .. text, text
end

------------------------------------------------------------------------
-- Guild information
------------------------------------------------------------------------
function GT:GetInfo()
    if GetGuildInfoText then return GetGuildInfoText() or "" end
    return ""
end

function GT:CanEditInfo()
    return IsInGuild() and CanEditGuildInfo ~= nil and CanEditGuildInfo() and true or false
end

-- Guild information can only be saved from Blizzard's Guild window (the
-- function is restricted and has no slash command). The Info tab drafts it
-- and opens that window via the guild micro button.
function GT:GuildButtonName()
    for _, name in ipairs({ "GuildMicroButton", "SocialsMicroButton" }) do
        if _G[name] then return name end
    end
end

------------------------------------------------------------------------
-- Guild news
------------------------------------------------------------------------
function GT:HasNews()
    return GetNumGuildNews ~= nil and C_GuildInfo ~= nil and C_GuildInfo.GetGuildNewsInfo ~= nil
end

function GT:QueryNews()
    if not self:HasNews() then return end
    if QueryGuildNews then QueryGuildNews() end
    if GuildNewsSort then GuildNewsSort(0) end -- respects filters and sticky items
end

function GT:CanSticky()
    return self:CanEditMOTD() and GuildNewsSetSticky ~= nil
end

function GT:SetSticky(index, sticky)
    if self:CanSticky() then GuildNewsSetSticky(index, sticky and 1 or 0) end
end

local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local LOOT = { [3] = true, [4] = true, [5] = true, [8] = true } -- looted, crafted, purchased, legendary

local function NewsText(info)
    local who = info.whoText or UNKNOWN or "Unknown"
    local what = info.whatText
    local t = info.newsType
    if what then
        if t == 1 then what = "|cffffff00[" .. what .. "]|r"                -- player achievement
        elseif t == 0 then who, what = "|cffffff00[" .. what .. "]|r", nil end -- guild achievement
    end
    local fmt = _G["GUILD_NEWS_FORMAT" .. tostring(t)]
    if fmt then
        local ok, text = pcall(string.format, fmt, who, what or "")
        if ok then return text end
    end
    return what and (who .. ": " .. what) or who
end

-- { { header = "Monday, 10/4" } or { index, text, sticky, link, type } , ... }
function GT:News()
    local out = {}
    if not self:HasNews() then return out end
    for i = 1, GetNumGuildNews() do
        local info = C_GuildInfo.GetGuildNewsInfo(i)
        if info then
            if info.isHeader then
                local day = (CALENDAR_WEEKDAY_NAMES and CALENDAR_WEEKDAY_NAMES[(info.weekday or 0) + 1]) or WEEKDAYS[(info.weekday or 0) + 1] or ""
                out[#out + 1] = { header = ("%s, %d/%d"):format(day, (info.month or 0) + 1, (info.day or 0) + 1) }
            else
                out[#out + 1] = {
                    index = i, text = NewsText(info), sticky = info.isSticky,
                    link = LOOT[info.newsType] and info.whatText or nil, type = info.newsType,
                }
            end
        end
    end
    return out
end

function GT:Filters()
    local out = {}
    if not GetGuildNewsFilters then return out end
    local values = { GetGuildNewsFilters() }
    for i, on in ipairs(values) do
        local label = _G["GUILD_NEWS_FILTER" .. i]
        if label then out[#out + 1] = { id = i, label = label, on = on and true or false } end
    end
    return out
end

function GT:SetFilter(id, on)
    if SetGuildNewsFilter then
        SetGuildNewsFilter(id, on and 1 or 0)
        self:QueryNews()
    end
end

------------------------------------------------------------------------
function GT:Init()
    local function changed() ns.Debounce("guildtext", 0.2, function() ns:Fire("GUILD_TEXT_UPDATED") end) end
    for _, event in ipairs({ "GUILD_MOTD", "GUILD_NEWS_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
        ns:RegisterEvent(event, changed)
    end
end
