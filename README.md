# Nootropic Guild Manager

A guild roster for **World of Warcraft: Forever** that shows each member's professions and specialization, links alts to their mains, tags what they enjoy (with icons), runs guild polls, lets officers rate how well they play their class and keep a dated officer log, records an audit trail of every change, and searches all of it. Shared data stays in sync between everyone running the addon.

## Install

1. Unzip so the folder sits at `Interface/AddOns/NootropicGuildManager` (the folder must be named exactly `NootropicGuildManager`).
   - Forever beta: `World of Warcraft/_classic_beta_/Interface/AddOns/`
   - After launch, use whichever `_classic..._` folder the Forever client installs into.
2. Restart the game or `/reload`, and make sure Nootropic Guild Manager is enabled on the character select AddOns screen.
3. If it shows as "out of date" after a patch, tick **Load out of date AddOns**, or update the `## Interface:` line in `NootropicGuildManager.toc` (`/dump select(4, GetBuildInfo())` prints your client's number).

## Opening it

- `/ngm` (or `/nootropic`), the minimap button, the addon compartment menu, or the **shortcut tab on the Guild & Communities window**.
- Minimap button: left-click opens the Roster, right-click the Options, shift-click Recruitment (all changeable in Options). Clicking again closes the window.
- Drag the grip in the bottom-right corner to resize the window. The size is saved.

## What you see

**Roster tab** — every guild member with first name (with class icon), second name, level, class, location (with a map button), spec, Main / Alt ("Main" or "Alt of Markpri"), up to three professions with skill levels, tags, a 1–5 star rating (officers only; hidden by default), guild rank, and the version of Nootropic Guild Manager they run (hidden by default; shown in red when someone in the guild has a newer version, "-" if they don't use the addon). Click a column header to sort; sorting by Main / Alt groups each main with their alts. Offline members are dimmed.

- **Right-click any column header** to show or hide columns. Your choice is saved between logins. Name can't be hidden.
- **Rearrange columns** by dragging a header left or right; a gold marker shows where it will land. The order is saved between logins. "Reset column order" in the Columns menu, or **Reset Roster Columns** in Options (order, widths and shown columns), puts things back.
- **Resize a column** by dragging the right edge of its header. Widths are saved; "Reset column widths" in the Columns menu undoes it. The last column fills the leftover space.
- **Smaller windows** shrink columns toward a minimum width, then hide them in this order: Rank, Class, Lvl, Location, Professions, Rating, Main / Alt, Tags, Spec, Second Name. First Name is never hidden. Hidden columns come back when you widen the window, and the Columns menu marks them "(window too narrow)".
- The **Spec** column and the profile show each class's talent-tree icon.

- **Click a member** to open the detail panel beside the roster.
- **Right-click a member** for quick tags, rating and main/alt (officers), whisper and invite.
- **Tags column** shows each tag's icon, framed in the tag's color. Hover the member to see every tag's icon and name in the tooltip.
- **The bar at the top:** search on the left, **Tags** and **Filter** on the right. **Tags** opens a list of every tag (icon and color) to tick, showing members with **all** ticked tags or **any** of them. **Filter** has **Online only**, **Show** (mains and alts, mains only, alts only), **Class**, **Rank** and **Only guildmates using the addon**, plus **Reset filters**; your filter choices are saved. The buttons show how many are on, e.g. "Tags (2)".
- **The summary line** under the bar shows members, how many are online and how many use the addon (and how many are showing when you search or filter). Active tags and filters are listed on its right, with **Clear** to turn them all off.
- **Export the roster:** right-click any column header and choose **Export roster...** (or type `/ngm export`). A window shows the roster as text, already selected: press Ctrl+C and paste it into Excel, Google Sheets, or Notepad (save as `.csv`). Choose **Members** (the ones shown on the roster with your search, tags and filters, or the whole guild), **Columns** (the roster's visible columns in your order, or every field: names, level, class, spec, main/alt and alts, location, last online, professions, tags, rank, addon version, public note) and **Separator** (tab pastes straight into spreadsheet columns; comma for a `.csv` file; or semicolon). Big exports are split into parts: type how many members per part in **Part size** (250 to start, anything from 10 to 5000), then copy each part and use **Next**; the column headings are only on part 1, so the parts paste together into one table. Rating and officer notes are only exported for officers, and your private notes only when you tick **Include my private notes**. Your choices are remembered.
- **Compact roster:** the red **Compact** button beside the close button (on the Roster tab) closes the big window and opens a small roster with no tabs that you can move and resize. It shows **First Name** and **Location**; right-click a column header to add Level, Class, Second Name, Spec, Main / Alt or Rank. Columns move (drag a header), resize (drag its edge) and hide just like on the Roster tab. It has its own search and **Online** box, sorts by clicking a header, and shows the same tooltip and right-click menu as the Roster tab. Click a name to open their profile in the full window, or the **expand arrow** to go back. `/ngm compact` shows or hides it.
- **"x using Nootropic Guild Manager"** at the bottom of the window (it says your guild's name instead when that option is on): click it to list only guildmates running the addon, with the Version column turned on. It turns on **Filter > Only guildmates using the addon**; click **Clear** on the summary line to see everyone again. Options can hide it.

**Character profile** — opens beside the roster when you click a member. It reads like a profile card, with an **Edit** button when you can change it.

- **Header**: name, "Level 22 Feral Druid - Veteran" (with the spec icon), online status and zone, and their **map dot** in the colors you'd see on the map (click it to open the map where they are). Under it, one line for **main / alts** (click a name to open that profile).
- **Status**: a short line they set ("Leveling to 30 this week, whisper me!") with how long ago they set it.
- **Pronouns** (off unless officers turn them on in **Options > Officers**): up to 24 characters, typed or picked from suggestions (he/him, she/her, they/them, he/they, she/they, any pronouns, ask me), shown in grey next to the name on the profile and in the roster tooltip. Alts without their own show their main's. Officers can clear someone's but not change them. Turning the option off hides everyone's pronouns without deleting them.
- **About me**: a few lines they write about themselves (up to 300 characters). An alt without one shows its main's. **Officers can clear** someone's About me (for anything inappropriate) but never edit it; the Audit tab records who did.
- **Tags**: only the tags they have.
- **Kudos**: thank-you badges from guildmates with counts (e.g. "Helpful x12"), from the last 90 days. **+ Give Kudos** (also in the roster's right-click menu) gives one: each kudos once a week per person, never to yourself. **Kudos are anonymous**: no name is saved or shown, and a kudos is sent a few minutes after you give it. (Like guild reviews, the game itself attaches your name to addon messages, which the addon discards; someone watching addon traffic with their own tools could still see it.) Defaults: Great Tank, Healer Hero, Damage Dealer, Group Leader, Helpful, Good Teacher, Generous, Good Vibes and Funny.
- **Usually online**: a one-line summary of when they usually play (e.g. "Mon-Fri 8 pm-11 pm - Sat-Sun 2 pm-12 am"). Times follow **your game clock**: if its **Use Local Time** box is ticked you see your local time, otherwise server time, and **24 Hour Mode** shows "20:00-23:00". **Show week** unfolds a week grid; hover a block to see it on the other clock too. Hours are **learned automatically**: while you play, your own copy of the addon notes the server hour every 10 minutes and keeps the last 4 weeks (an hour counts once you've played it in two different weeks), and only the result is shared. Everything is kept in server time, the same for the whole guild, so no time zone settings are needed.
- **Tabs**: **Profile** (professions: primary first, then secondary; the ones their addon reports stay up to date by themselves), **Notes** (your **private notes** about them; only you ever see these), and **Officer** (officers only: **rating**, the **officer log** and **change history**).
- **Edit** (your own characters, or anyone for officers): **About me**, **Status**, **Usually online** (folded at first; **Edit hours** shows **Learn my hours from when I play** and, for each day, **Learned**, **Not playing** or **Set hours** with a from-to time in server time), and your **map dot** colors (only your own profile); plus **specialization**, **tags** (all of them, click to turn on or off), **professions** (add, remove, set levels) and, for officers, **main & alt links**. **Done** goes back.

Officers manage the **kudos list** on the Tags tab (**Tags / Kudos** switch at the top): add up to 12, edit their name, icon, color and a short **description** (up to 255 characters, shown in the tooltip when you hover a kudos on a profile, in the Give Kudos menu and on the Tags tab; the default kudos come with one), reorder them, or **Retire** one (nobody can give it any more; ones already given stay until they're 90 days old; retired kudos fold up at the bottom of the list, and **Bring Back** undoes it).

**Recruitment tab**

1. The search bar reads **Name**, **Zone**, **Level**, **Filter**, **Search**. Click **Search** (it runs the game's own `/who` through a secure button, the approved way for addons, so it can't be used in combat). To keep you clear of spam detection, searches are limited to one every 15 seconds and 12 per 5 minutes; the button counts down until the next one is allowed. Everyone without a guild (who isn't already in yours) is added to the list. The game returns at most 50 players per search and limits how often you can search, so use narrow level ranges.
   - **Zone** starts as the zone you're in and **Level** as 3 levels below you to 2 above, and both follow you as you travel and level. Type your own to keep it; clear the box (both level boxes) to follow you again.
   - **Name:** type part of a character's name to show only matching players in the list right away; **Search** also looks for that name, so you can find a specific character. Clear it to see everyone again.
   - **Filter** opens a small menu: **Class**, **Step levels** (after each search the level range moves up by its own size, wrapping back to 1 at max level; keep clicking Search to sweep every level), **Hide contacted**, and **Search a guild instead** (type a guild name to find members of that guild instead of players without one, for recruiting from other guilds; matches the name or its beginning; your own guild is never included). **Reset filters** turns them all off. The Filter button shows how many are on, e.g. "Filter (2)".
   - The line under the search bar sums things up: players in the list, how many were new in the last search, how many you've whispered and how many replied, plus warnings (search capped at 50, Do Not Whisper players skipped). Active filters are listed on its right.
   - **Columns** work like the Roster tab's: drag a header sideways to move it, drag its edge to resize it, and right-click any header to show or hide columns (Lvl, Class, Zone, Status) or reset them. The tick box and Name always stay.
2. **Tick the players you want to message** (click the checkbox or anywhere on the row). **Select New** ticks every player nobody in the guild has contacted; **Clear** unticks all; **Clear New** (beside them) removes everyone you haven't contacted from the list. Hover a row to read the message that player will get.
3. Click **Send Whispers (N)**. Whispers go out one at a time, at least 12 seconds apart and no more than 40 per hour, so the game never sees the addon as a spammer. The button shows the countdown and turns into **Stop** while sending. If the game ever refuses an automatic whisper, the addon switches to click-to-send: the button becomes **Send Next** and each click sends one (same pacing).
4. The Status column tracks each player: New, Queued, Whispered, Replied, Invited, and Joined! (detected automatically when they appear in your roster). Contacted players stay in the list so you never message anyone twice; **Clear New** removes only the uncontacted ones and **Hide contacted** (in Filter) hides the contacted ones.
   - **Statuses are shared with the guild.** When anyone running the addon whispers, hears back from, or invites a player, everyone else sees it ("Whispered 2 hr ago by Mira") and can't tick that player, so nobody is whispered twice by the same guild. Hover the row to read their reply. Shared statuses are kept for 7 days, then forgotten; your own list keeps your own history.
5. **Keep playing while you recruit:** click the red **Compact** button beside the close button (on the Recruitment tab) to close the big window and show a small recruiting bar you can drag anywhere. It shows what's happening (countdown to the next whisper, players found, how many are ready) and has **Search**, **Select New** and **Send / Stop / Send Next**, so you can search, tick and send without opening the window. Its **expand arrow** goes back to the full tab; the X hides the bar (queued whispers keep sending). If you close the main window while whispers are still being sent, the bar appears by itself. `/ngm mini` shows or hides it.
6. **Whisper from the game's /who window:** every player in the game's own /who search (the Looking For Group people search) gets a small letter button beside the group-invite button. One click sends that player your recruitment whisper, exactly as from the Recruitment tab: your custom messages when **Use custom messages** is on (otherwise the Default message), with the same spacing between whispers (it joins the whisper queue, and the small recruiting bar appears if the main window is closed). Hover the button to read the message they'll get. The player is added to your Recruitment list and their status is shared with the guild. The button is grayed out (hover it to see why) for members of your guild, people on the Do Not Whisper list, and players you or a guildmate already contacted; it shows "..." while queued and a check once whispered. On by default; **Options > Recruiting** turns it off. If the buttons don't appear, search with the window open and run `/ngm diag`.
7. **Invites only after a whisper** (on the Recruitment tab). Right-click a player to invite them; the option stays unavailable ("whisper them first") until they've been whispered. Right-click also offers a one-off custom whisper and removing them.

**Default message** (right side): the whisper for anyone no custom message matches. These are filled in for you:

| Token | Becomes |
| --- | --- |
| `$name` | their character name |
| `$class` | their class |
| `$level` | their level |
| `$race` | their race |
| `$zone` | the zone they're in |
| `$guild` | your guild's name in angle brackets, e.g. `<Knights of Azeroth>` |

A live preview shows the result. Whispers are limited to 255 characters.

**Custom messages**: tick **Use custom messages** and click **Custom Messages...** to open the editor. Each message has filters, and a player gets the first enabled message (top to bottom) whose filters all match them; anyone left over gets the Default message. Filters left empty match everyone:

- **Class** (any of the ticked classes) and **Race** (your faction's four races, each shown with its male and female portrait)
- **Level** range (1 to 60 unless you change it)
- **Zones**: comma-separated, matching any part of the zone name (`Elwynn, Westfall`)
- **Guild**: Any, No guild, or In a guild (for messages to players found with the Guild search)

Order is priority: use the up/down arrows to move a message. Put specific messages ("Night Elf Druids in Darkshore") above broad ones ("Druids"). **New**, **Copy** (duplicate and tweak) and **Delete** manage the list, and the enable box beside each message turns it off without deleting it. While you edit, the window shows how many players in the current search match the filters, how many will actually get this message (others may be taken by a message above it), and a preview for one of them. There's no gender filter: the game doesn't reliably say a player's gender.

**Built-in class messages**: a ready-made, friendly message for every class is added for you (turned on, after any messages of your own). That includes Paladins and Shamans for both factions, since WoW: Forever lets either faction play them; guilds that set up their messages before 1.13 get the one they were missing (Paladin for Horde, Shaman for Alliance) added once, turned on. Edit them, switch them off or delete them; **Class Defaults** adds back any class that's missing one.

**Import / Export**: **Export...** shows every message as plain text to copy (Ctrl+C) and share on Discord, a website or a text file. **Import...** takes that text (Ctrl+V) and either adds the messages after yours or replaces your whole list. The format is easy to write by hand:

```
message: Night Elf Druids
on: yes
classes: Druid
races: Night Elf
levels: 10-60
zones: Teldrassil, Darkshore
guild: any
text: Hi $name! $guild would love a Druid from $zone. Reply "invite" to join.
```

Each message starts with `message:`. Lines you leave out mean "any"; `guild` is `any`, `none` or `guilded`; `#` lines are ignored. Anything the importer can't read is reported, and the rest still imports.

**Auto-invite** (set up in **Options > Recruiting**): when a player you whispered from this tab replies with one of your up to 5 keywords, Nootropic Guild Manager sends them a guild invite. Keywords match whole words in any case (`join` matches "Join pls" but not "joining"), and can be phrases like `sign me up`. Replies from anyone you didn't whisper here are ignored. Because WoW: Forever only allows guild invites from a click, this shows a one-click **Invite** popup by default (**Ask me first** is on). Untick it on clients that allow fully automatic invites.

**Do Not Whisper list** (on by default, **shared with the guild**, set up in **Options > Recruiting**): when someone you whispered replies with one of up to 5 words or phrases (defaults: `dnw`, `leave me alone`, `do not whisper`, `stop whispering`, `not interested`; whole words, any case), they're added to the list. The list syncs to everyone in the guild running the addon, so once one recruiter is told to stop, nobody in the guild bothers that player again. People on it show "Do not whisper", can't be ticked, whispered or invited, and are skipped by future searches. This check runs before the invite keywords, so "yes, but leave me alone" never invites. **View List** shows who's on it, when and by whom (click a name to take them off for everyone), and right-clicking a player adds or removes them by hand. Additions and removals appear in the Audit tab. Unticking the box stops adding people; anyone already listed stays protected.

Messages and keywords are saved per guild.

**Polls tab** — guild polls and guild stats.

- **Officers** create polls: a question (up to 120 characters) and 2 to 6 answers. Choose when voting closes in minutes, hours or days (1 week by default), and how many days the results stay after it closes (7 by default, 0 to 365). Officers can also close voting early or delete a poll.
- **Everyone** running the addon can vote, and change their vote until the poll closes. Results (votes and percentages for each answer) show while it's open and after it closes, until its days are up; then the poll is deleted. Only votes cast before a poll closed are counted.
- The list shows **Open Polls** (closing soonest at the top), then **Guild Stats**, then **Closed Polls**. The tab opens on an open poll you haven't voted on, if there is one. You get a chat message the first time you see a new poll you haven't voted on.
- Votes are shared with everyone running the addon, like tags; they aren't secret ballots.
- Every poll's results show as bars and a **pie chart**, each answer in its own color. Hover an answer to light up its slice, or a slice to light up its answer.
- **Guild Stats** look like closed polls nobody votes on, worked out live from the roster: Classes (in class colors), Levels, Ranks, Professions, Mains and alts, Addon users, Busiest days and Busiest times (from everyone's usual online hours, in your game clock's time; alts count with their main) and Kudos given (last 90 days). Hover a row or slice for the count and percentage; click it to see those members in the roster.

**Reviews tab** (the last tab; called **Review Guild** for members) — anonymous reviews of the guild.

- **Officers can turn reviews off** for the whole guild (the **Guildmates can review the guild** box on the tab, or in Options). While off, members don't see the Review Guild tab and can't write reviews; officers still see every review.
- **Everyone** can rate the guild 1-5 stars and write a message (up to 500 characters), once every 7 days.
- **Only officers** can read reviews. They see the average rating, how many reviews gave each number of stars, and every review from the last year, newest first. Click one to read it and see the officer comments.
- **Officer comments**: officers can comment on a review; other officers see the comment with its author's name. You can delete your own comments, nobody else's.
- **Nobody can change or delete a review**, officers included. Reviews and comments are kept for a year, then deleted.
- **How it stays anonymous**: a review never carries a name. Its id is random, it's dated by day only, and it isn't sent when you click Submit but 2-15 minutes later. It goes to a single officer running the addon (not the whole guild); that officer's copy saves it without a name and shares it with the other officers at low priority on the officer channel. If no officer with the addon is online, it waits (up to 30 days) and is sent when one is.
- **What an addon can't hide**: the game itself attaches the sender's name to every addon message, so the receiving officer's game client briefly knows who sent it. Nootropic Guild Manager discards that name and never saves or shows it, but someone running their own tools to watch addon traffic at that moment could see it. The 7-day limit is remembered by your own copy of the addon (per account and guild), since the guild can't know who wrote what.

**Tags tab** (officers only) — manage the guild's tags and kudos, picked with the **Tags / Kudos** switch at the top. The list is on the left with each one's count (members with the tag, or kudos given in the last 90 days); click one to edit it on the right: its name, an **icon** (click the big icon or **Change...** to pick any icon from the game's macro icon menu, or **paste** one found outside the game: its name like `inv_misc_head_murloc_01`, its file number like `134169`, or a Wowhead icon link; a preview shows whether this version of the game has it), a **color** (Gold, Azure, Violet, Crimson, Ember, Jade, Moss, Frost, Rose, Silver) and its order, with a preview. **Save** keeps your changes, **Undo** drops them. The editor also shows who has a tag (**Show in Roster** lists them there) or who got a kudos most. **Delete** removes a tag from everyone; kudos are **Retired** instead and fold into **Retired (n)** at the bottom of the list. **+ New Tag** / **+ New Kudos** starts a new one in the same editor. Right-click a row for Move Up, Move Down and Delete / Retire. Tags are shared with everyone in the guild running the addon. Ten tags are created to start, each with its own icon: Questing, Dungeons, Raiding, World PvP, Battlegrounds, Crafting, Gathering, Leveling, Roleplay, Social.

Members can tag **themselves** (on their own profile or by right-clicking their own row); only officers can tag other people.

**Audit tab** (officers only) — every synced change across the guild: when, who changed it, which character, and what changed (e.g. "Rating changed from ★★ to ★★★" shown as star icons, "+Raiding", "Marked as an alt of Markpri"). Search it, filter by kind of change (tags, rating, main/alt, spec, professions, officer log, tag list, tag icons, polls, guild settings such as turning reviews off) or by character, and click a row to open that profile. Changes saved together (within one 15-second batch, see below) are grouped into one line; hover it to see each change, or untick **Group changes**. How long history is kept is set in Options.

## Who can do what

| | Everyone with the addon | Officers |
| --- | --- | --- |
| See roster, tags, mains/alts, specs, professions | yes | yes |
| Add to or remove from the Do Not Whisper list | yes | yes |
| Share recruitment statuses | yes | yes |
| Write an anonymous guild review (every 7 days, while reviews are on) | yes | yes |
| Read reviews, comment on them, turn reviews on or off | | yes |
| Vote in polls (and change the vote until it closes) | yes | yes |
| Create, close and delete polls | | yes |
| Write your own About me, status and usual online hours; give anonymous kudos | yes | yes |
| Clear someone's About me; manage the kudos list | | yes |
| Edit their **own** tags, spec and professions | yes | yes |
| Edit anyone's tags, spec, professions, mains/alts | | yes |
| See and edit ratings | | yes |
| Officer Log, Change History, Audit tab, Tags tab | | yes |
| Turn pronouns on profiles on or off; clear someone's pronouns | | yes |

"Officers" are ranks that can read officer notes (the game's own permission). If someone is promoted or demoted, the addon updates on the spot.

## Guildmates on the map

Every copy of the addon shares its player's map position with the guild (every 15 seconds while moving, once a minute standing still; never inside dungeons). Guildmates appear on the world map as dots in their class color, on zone and continent maps. Hover a dot for the same details as the roster tooltip; click it to open their profile. The roster's **Location** column shows each guildmate's zone followed by their map dot (in the same colors as on the world map: class color, or their own colors when custom dots are on in Options); click the dot to open the map there and highlight them.

Both are on by default. Options has separate switches to stop sharing your own location and to hide the dots.

**Custom dot colors** (off by default): turn it on in Options to see the colors guildmates picked for their dots, and to pick your own dot color and outline color (with a preview and a **Use Class Color** reset). With it off, every dot is its class color with a black outline. Your colors are shared with the guild and only show for people who turned the option on. Positions are never saved or audited and disappear after 3 minutes without an update.

## Options

Open from **Options > AddOns > Nootropic Guild Manager**, `/ngm options`, shift-clicking the minimap button, or right-clicking the addon compartment entry.

Options has four pages in the game's AddOns list:

- **Nootropic Guild Manager** (main page)
  - **Appearance**: the **addon icon** (Ale Mug, Brewfest Stein or your **Guild Emblem**, shown on the window, the minimap button and the Guild & Communities shortcut; the emblem falls back to the mug outside a guild or without a tabard), **use my guild's name in the window title** (also in the "x using ... Guild Manager" text), **show how many guildmates use the addon** (on by default), and the **shortcut on the Guild & Communities window**.
  - **Minimap Button**: show/hide it, and choose what left-click, right-click and shift-click do (Roster, Recruitment, Polls, Tags, Audit, Reviews, Options, show/hide window, or nothing).
  - **Reset**: window size and position, list columns (roster, compact roster and recruitment list), and the compact roster and recruiting bar positions.
  - **About**: sync stats with a **Sync Now** button, **Open Guild Manager**, and the most useful commands.
- **Recruiting** (saved per guild): the **recruitment whisper button on /who results** (on by default), **Auto-Invite** (invite on a keyword reply, ask me first, up to 5 keywords) and **Do Not Whisper** (on/off, up to 5 words, and the shared list). The Recruitment tab shows how these are set under **Replies**, with a **Reply Settings...** button that opens this page.
- **Map**: share my location, show guildmates on the world map, and custom dot colors (whether you see guildmates' chosen colors). **Change My Dot...** opens your profile in Edit mode to pick your own.
- **Officers**: **Guildmates can review the guild** (whole guild) and **Audit History** (keep 30, 60 or 90 days on your copy). Members see this page but can't change it.

## Searching

Type any words. A member is shown when every word matches their name, class, spec, professions or tags.

| Query | Finds |
| --- | --- |
| `warrior protection` | protection warriors |
| `tailoring enchanting` | members with both professions |
| `tag:raiding` | the Raiding tag only |
| `tag:"world pvp"` | quotes keep a phrase together |
| `prof:herb` `spec:holy` `class:mage` `name:ann` | one field only |
| `rank:officer` `zone:stormwind` `note:healer` | rank, zone, notes |
| `rating:4` | four stars or better (`rating<2`, `rating=5` also work) |
| `level>=55` | level filter |
| `main:markpri` | Markpri and all their alts |
| `is:alt` / `is:main` | only alts / only mains |
| `is:addon` | only guildmates running Nootropic Guild Manager |
| `-raiding` | exclude a match |

`/ngm find <text>` opens the roster with a search already typed.

## Where professions and specs come from

The game does not let addons read another player's professions or talents. Nootropic Guild Manager handles this two ways:

- **Members running Nootropic Guild Manager** share their own professions and spec automatically over the hidden guild addon channel when they log in, when they change talents or skills, and when someone opens the roster, and every few minutes (or right away with **Sync Now** in Options or `/ngm sync`). A green check marks synced data.
- **Everyone else** can be filled in by hand from the detail panel. Synced data takes priority for professions; a manual spec always wins over a synced one.

Spec is detected from the modern specialization API when the client has it, otherwise from whichever talent tree has the most points (shown as a split like `5/31/15`).

## Mains and alts rules

- Links always point at the top-level main. Marking a character as an alt of someone's alt links it to that main instead.
- Marking a main (who has alts) as an alt moves their whole family to the new main.
- **Make This Main** swaps roles when a player changes which character they main.

## How syncing works

Every shared value (a member's tags, main, spec, professions, rating, an officer log entry, a tag definition or icon, a poll, a vote, a guild setting) is stored with the time it was changed and who changed it. The newest change always wins, so everyone ends up with the same data no matter the order messages arrive in.

- **Batches:** your changes show up for you instantly but are sent 15 seconds after the first one, all together. Everything in one batch is grouped in the audit.
- **Repair:** every few minutes, and whenever you open the window, each copy of the addon sends a short checksum of its data. If a guildmate's checksums differ, the records that differ are re-sent on the same channel, and other clients skip re-sending what someone just sent. Missed messages, officers who were offline, and new installs all catch up this way, with no "Sync" button needed. Nothing is ever whispered.
- **Officer-only data** (ratings, officer log, audit) only ever travels on the game's officer addon channel, which the game delivers only to officer ranks.
- **Pacing:** messages are rate-limited to stay well under the game's limits; if the game reports throttling, messages are retried rather than lost.

In testing, three simulated clients (two officers and a member) with 40-50% of messages randomly dropped, one officer offline while others made changes, and conflicting edits all ended up identical.

`/ngm sync` runs a sync immediately and shows counts of messages sent, received and applied.

## Your data

Everything is saved per guild in `WTF/Account/<account>/SavedVariables/NootropicGuildManager.lua`, along with your settings. **Private notes never leave your computer**; shared data syncs as described above.

What is shared:
- With everyone running the addon: each player's own professions and spec, tags (with their icons and colors), mains/alts, spec/profession overrides, the Do Not Whisper list, and recruitment statuses (the last 7 days), map dot colors, which addon version each person runs, polls and everyone's votes (until the poll's results expire), and whether officers have turned guild reviews off.

Guildmates on 1.11 or older ignore polls, tag icons and the reviews switch; everyone should update to 1.12 so the guild stays in sync.
- With officers only: guild reviews (anonymous) and officer comments on them, ratings, Officer Log entries (140 characters max; deleting one deletes it for every officer) and the audit trail.

A note on trust: the addon checks permissions before sending anything, and officer data can only arrive through the officer channel. A guildmate who modified their copy of the addon could still forge a guild-wide change, but every change is recorded in the Audit tab with its author, so it would be visible to officers.

## Commands

| Command | Does |
| --- | --- |
| `/ngm` | open or close |
| `/ngm find <text>` | open with a search |
| `/ngm recruit` | open the Recruitment tab |
| `/ngm mini` | show or hide the small recruiting bar |
| `/ngm compact` | show or hide the compact guild roster |
| `/ngm export` | copy the roster as text for a spreadsheet or `.csv` file |
| `/ngm options` | open the options |
| `/ngm diag` | report what the Guild & Communities shortcut and the /who whisper buttons can see, and which name and version the addon uses for you |
| `/ngm perf` | performance this session: memory use, sync traffic, stored records, and how often the roster and map dots were rebuilt and redrawn |
| `/ngm sync` | sync now and show sync stats |
| `/ngm polls` | open the Polls tab |
| `/ngm audit` | open the Audit tab (officers) |
| `/ngm reviews` | open the Reviews tab (Review Guild for members, while reviews are on) |
| `/ngm minimap` | show or hide the minimap button |
| `/ngm reset` | reset the window size and position |

## Code layout

```
NootropicGuildManager.toc
Core/      Core.lua (namespace, events, utils, slash)  Data.lua (classes, specs, professions, tags)  Database.lua (saved data)  Sync.lua (records, repair, transport)
Services/  Location.lua (shared positions)  Roster.lua (roster, search, sort)  Comm.lua (own spec/professions)  Recruit.lua (/who, whisper queue, invites)  Messages.lua (custom message rules)  Audit.lua (change descriptions)  Reviews.lua (anonymous guild reviews)  Polls.lua (guild polls)  Stats.lua (guild stats)  Profile.lua (About me, status, usually online, kudos)
UI/        Widgets.lua  Columns.lua  PieChart.lua  ScheduleGrid.lua  BrandIcon.lua  MemberPicker.lua  IconPicker.lua  RosterView.lua  CompactRoster.lua  ExportView.lua  RecruitView.lua  RecruitMini.lua  MessagesView.lua  DetailPanel.lua  PollsView.lua  TagsView.lua  AuditView.lua  ReviewsView.lua  MainFrame.lua  MinimapButton.lua  MapPins.lua  Options.lua  Communities.lua  WhoWhisper.lua
```

## Names in WoW: Forever

Forever characters have a first and second name (e.g. "Audrey Pichhale") and no realms. The addon whispers and invites by the plain name, never "Name-Realm", and shows the two names in separate roster columns.
