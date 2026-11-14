-- Test: Invite prompt: the /ginvite command to copy, queueing, the "You have invited" confirmation, and never touching the chat box.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
ns.GOLD, ns.ORANGE, ns.BLUE = "|cfffabd2f", "|cfffe8019", "|cff83a598" -- Core.lua sets these
function ns:Print() end
function ns.PlaySound() end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.ChatName(n) return (n:gsub("%-.*", "")) end
ns.Widgets = {}
local chatTouched = false
ChatFrameUtil = { OpenChat = function() chatTouched = true end }
ChatFrame_OpenChat = function() chatTouched = true end
local invited = {}
ns.Recruit = { CanInviteNow = function() return true end, MarkInvited = function(_, f) invited[#invited + 1] = f end }
assert(loadfile(ROOT .. "/UI/InvitePrompt.lua"))("NGM", ns)
local IP = ns.InvitePrompt
local fs = function() return { SetText = function() end } end
local boxText, focused = "", false
IP.box = { SetText = function(_, t) boxText = t end, HasFocus = function() return focused end,
  SetFocus = function() focused = true end, ClearFocus = function() focused = false end, HighlightText = function() end }
IP.frame = { IsShown = function() return true end, Show = function() end, Hide = function() end }
IP.Build = function() end
IP.text, IP.more, IP.hint, IP.inviteButton = fs(), fs(), fs(), fs()
IP:Show("Audrey Pichhale-Realm", "yeah"); IP:Show("Bob Two-Realm", "sure")
assert(boxText == "/ginvite Audrey Pichhale")
IP:SelectCommand(); assert(focused and boxText == "/ginvite Audrey Pichhale")
IP:OnSystemMessage("You have invited Audrey Pichhale to join your guild.")
assert(invited[1] == "Audrey Pichhale-Realm" and IP.full == "Bob Two-Realm" and boxText == "/ginvite Bob Two" and not focused)
assert(not chatTouched, "the addon touched the chat box")
print("box:", boxText, " invited:", invited[1]); print("OK")
