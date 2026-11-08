# Nootropic Guild Manager

A guild manager for **World of Warcraft: Forever**: a searchable roster with professions and specs, a main/alt manager, tags, contact info (Discord names and notes), when people usually play, a dated officer log, an audit trail of every change, and recruiting tools that only ever message players without a guild. The Guild Master decides which ranks can do what. Shared data stays in sync between everyone in the guild running the addon.

**Version 2.0** is the launch release. It's a slimmed-down build: guild reviews, ratings, map sharing, polls/stats/goals (Insights), kudos, About me/status/pronouns, the compact roster, the recruiting bar, roster export and tab customization are gone. It syncs on a new protocol: guildmates on 1.x and 2.0 don't sync with each other, so everyone should update.

## Install

1. Unzip so the folder sits at `Interface/AddOns/NootropicGuildManager` (the folder must be named exactly `NootropicGuildManager`).
   - Use the `Interface/AddOns` folder inside the `_classic..._` folder the Forever client installs into (the beta used `_classic_beta_`).
2. Restart the game or `/reload`, and make sure Nootropic Guild Manager is enabled on the character select AddOns screen.
3. If it shows as "out of date" after a patch, tick **Load out of date AddOns**, or update the `## Interface:` line in `NootropicGuildManager.toc` (`/dump select(4, GetBuildInfo())` prints your client's number).

## Opening it

- `/ngm` (or `/nootropic`), the minimap button, the addon compartment menu, or the **shortcut tab on the Guild & Communities window**.
- Minimap button: left-click opens Find, right-click the Options, shift-click Recruitment (all changeable in Options). Clicking again closes the window.
- Drag the grip in the bottom-right corner to resize the window. The size is saved.

## What you see

**On the game's Guild & Communities roster** — Nootropic Guild Manager works on top of Blizzard's own guild roster rather than replacing it:

- **After each name**: up to three of their tag icons, and "alt" for alts.
- **Hover a member**: Blizzard's tooltip gets this addon's details underneath: main or alts, spec, roles, professions with skill levels, Discord, when they usually play, and their tags.
- **Right-click a member**: **Profile**, **Tags** (tick to add or remove, if your rank may) and **Main / Alt** (mark as alt, change main, make main, unlink, add an alt; if your rank may) are added to Blizzard's menu.
- **Alt+click a member** (or **Profile** in the menu) opens their profile docked beside the window, next to Blizzard's own member details when those are open.
- Only shown on your guild, not other communities. **Options > Show tags and alts on the Guild roster** turns all of it off. Nothing Blizzard does is changed or replaced, so inviting, promoting and removing keep working normally.

**Find tab** (in this addon's window) — for what the game's roster can't do: search by tags, professions, spec, Discord and more (see **Searching**), group mains with their alts, and filter by tags. It lists every guild member with first name (with class icon), second name, level, class, location, spec, Main / Alt ("Main" or "Alt of Markpri"), up to three professions with skill levels, tags, guild rank, and the version of Nootropic Guild Manager they run (hidden by default; shown in red when someone in the guild has a newer version, "-" if they don't use the addon). Second name, level, class, location and rank start hidden, since the game's roster shows them; turn them on from the Columns menu. Click a column header to sort; sorting by Main / Alt groups each main with their alts. Offline members are dimmed.

- **Right-click any column header** to show or hide columns. Your choice is saved between logins. Name can't be hidden.
- **Rearrange columns** by dragging a header left or right; a gold marker shows where it will land. The order is saved between logins. "Reset column order" in the Columns menu, or **List Columns** in Options (order, widths and shown columns), puts things back.
- **Resize a column** by dragging the right edge of its header. Widths are saved; "Reset column widths" in the Columns menu undoes it. The last column fills the leftover space.
- **Smaller windows** shrink columns toward a minimum width, then hide them in this order: Rank, Class, Lvl, Location, Professions, Main / Alt, Tags, Spec, Second Name. First Name is never hidden. Hidden columns come back when you widen the window, and the Columns menu marks them "(window too narrow)".
- The **Spec** column and the profile show each class's talent-tree icon.

- **Click a member** to open the detail panel beside the roster.
- **Right-click a member** for quick tags and main/alt (if your rank may), whisper and invite.
- **Tags column** shows each tag's icon, framed in the tag's color. Hover the member to see every tag's icon and name in the tooltip.
- **The bar at the top:** search on the left, **Tags** and **Filter** on the right. **Tags** opens a list of every tag (icon and color) to tick, showing members with **all** ticked tags or **any** of them. **Filter** has **Online only**, **Show** (mains and alts, mains only, alts only), **Class**, **Rank** and **Only guildmates using the addon**, plus **Reset filters**; your filter choices are saved. The buttons show how many are on, e.g. "Tags (2)".
- **The summary line** under the bar shows members, how many are online and how many use the addon (and how many are showing when you search or filter). Active tags and filters are listed on its right, with **Clear** to turn them all off.
- **"x using Nootropic Guild Manager"** at the bottom of the window (it says your guild's name instead when that option is on): click it to list only guildmates running the addon, with the Version column turned on. It turns on **Filter > Only guildmates using the addon**; click **Clear** on the summary line to see everyone again. Options can hide it.

**Character profile** — opens beside the roster when you click a member. It reads like a profile card, with an **Edit** button when you can change it.

- **Header**: name, "Level 22 Feral Druid - Veteran" (with the spec icon), online status and zone. Under it, one line for **main / alts** (click a name to open that profile).
- **Contact**: their **Discord** name (click it to copy) and a contact note (up to 80 characters: BattleTag, timezone, "DM me before raids"). Set by the member, or by anyone whose rank may edit other guildmates' profiles (handy for guildmates without the addon). Alts without their own show their main's. Searchable with `discord:`.
- **Tags**: only the tags they have.
- **Usually online**: a one-line summary of when they usually play (e.g. "Mon-Fri 8 pm-11 pm - Sat-Sun 2 pm-12 am"). Times follow **your game clock**: if its **Use Local Time** box is ticked you see your local time, otherwise server time, and **24 Hour Mode** shows "20:00-23:00". **Show week** unfolds a week grid; hover a block to see it on the other clock too. Hours are **learned automatically**: while you play, your own copy of the addon notes the server hour every 10 minutes and keeps the last 4 weeks (an hour counts once you've played it in two different weeks), and only the result is shared. Don't want that? Untick **Learn when I usually play** in Options; nothing is noted or shared then. Everything is kept in server time, the same for the whole guild, so no time zone settings are needed.
- **Tabs**: **Profile** (professions: primary first, then secondary; the ones their addon reports stay up to date by themselves), **Notes** (your **private notes** about them; only you ever see these), and **Officer** (officers only: the **officer log** and **change history**).
- **Edit** (your own characters, or others if your rank may): **Contact**, **specialization**, **roles**, **tags** (all of them, click to turn on or off), **professions** (add, remove, set levels) and **main & alt links**. **Done** goes back.

**Recruitment tab**

1. The search bar reads **Name**, **Zone**, **Level**, **Filter**, **Search**. Click **Search** (it runs the game's own `/who` through a secure button, the approved way for addons, so it can't be used in combat). To keep you clear of spam detection, searches are limited to one every 15 seconds and 12 per 5 minutes; the button counts down until the next one is allowed. Everyone without a guild (who isn't already in yours) is added to the list. Players in a guild are never listed or messaged, here or from the /who window's whisper button. The game returns at most 50 players per search and limits how often you can search, so use narrow level ranges.
   - **Zone** starts as the zone you're in and **Level** as 3 levels below you to 2 above, and both follow you as you travel and level. Type your own to keep it; clear the box (both level boxes) to follow you again.
   - **Name:** type part of a character's name to show only matching players in the list right away; **Search** also looks for that name, so you can find a specific character. Clear it to see everyone again.
   - **Filter** opens a small menu: **Class**, **Step levels** (after each search the level range moves up by its own size, wrapping back to 1 at max level; keep clicking Search to sweep every level), and **Hide contacted**. **Reset filters** turns them all off. The Filter button shows how many are on, e.g. "Filter (2)".
   - The line under the search bar sums things up: players in the list, how many were new in the last search, how many you've whispered and how many replied, plus warnings (search capped at 50, Do Not Whisper players skipped). Active filters are listed on its right.
   - **Columns** work like the Roster tab's: drag a header sideways to move it, drag its edge to resize it, and right-click any header to show or hide columns (Lvl, Class, Zone, Status) or reset them, like the Find tab's. The tick box and Name always stay.
2. **Tick the players you want to message** (click the checkbox or anywhere on the row). **Select New** ticks every player nobody in the guild has contacted; **Clear** unticks all; **Clear New** (beside them) removes everyone you haven't contacted from the list. Hover a row to read the message that player will get.
3. Click **Send Whispers (N)**. Whispers go out one at a time, at least 12 seconds apart and no more than 40 per hour, so the game never sees the addon as a spammer. The button shows the countdown and turns into **Stop** while sending. If the game ever refuses an automatic whisper, the addon switches to click-to-send: the button becomes **Send Next** and each click sends one (same pacing).
4. The Status column tracks each player: New, Queued, Whispered, Replied, Invited, and Joined! (detected automatically when they appear in your roster). Contacted players stay in the list so you never message anyone twice; **Clear New** removes only the uncontacted ones and **Hide contacted** (in Filter) hides the contacted ones.
   - **Statuses are shared with the guild.** When anyone running the addon whispers, hears back from, or invites a player, everyone else sees it ("Whispered 2 hr ago by Mira") and can't tick that player, so nobody is whispered twice by the same guild. Hover the row to read their reply.
   - **14-day lockout.** Once anyone in the guild whispers a player, **nobody in the guild (including you) can queue another recruitment whisper to them for 14 days**. The row can't be ticked and its tooltip says when they can be whispered again. Shared statuses are kept for those 14 days, then forgotten; your own list keeps your own history.
5. **Whisper from the game's /who window:** every player in the game's own /who search (the Looking For Group people search) gets a small letter button beside the group-invite button. One click sends that player your recruitment whisper, exactly as from the Recruitment tab: your custom messages when **Use custom messages** is on (otherwise the Default message), with the same spacing between whispers (it joins the whisper queue, which keeps sending while the window is closed). Hover the button to read the message they'll get. The player is added to your Recruitment list and their status is shared with the guild. The button is grayed out (hover it to see why) for anyone in a guild (yours or another), people on the Do Not Whisper list, and players anyone in your guild whispered in the last 14 days; it shows "..." while queued and a check once whispered. On by default; **Options > Recruiting** turns it off. If the buttons don't appear, search with the window open and run `/ngm diag`.
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

Order is priority: use the up/down arrows to move a message. Put specific messages ("Night Elf Druids in Darkshore") above broad ones ("Druids"). **New**, **Copy** (duplicate and tweak) and **Delete** manage the list, and the enable box beside each message turns it off without deleting it. While you edit, the window shows how many players in the current search match the filters, how many will actually get this message (others may be taken by a message above it), and a preview for one of them. There's no gender filter: the game doesn't reliably say a player's gender.

**Built-in class messages**: a ready-made, friendly message for every class is added for you (turned on, after any messages of your own). That includes Paladins and Shamans for both factions, since WoW: Forever lets either faction play them; guilds that set up their messages on older versions get the one they were missing (Paladin for Horde, Shaman for Alliance) added once, turned on. Edit them, switch them off or delete them; **Class Defaults** adds back any class that's missing one.

**Import / Export**: **Export...** shows every message as plain text to copy (Ctrl+C) and share on Discord, a website or a text file. **Import...** takes that text (Ctrl+V) and either adds the messages after yours or replaces your whole list. The format is easy to write by hand:

```
message: Night Elf Druids
on: yes
classes: Druid
races: Night Elf
levels: 10-60
zones: Teldrassil, Darkshore
text: Hi $name! $guild would love a Druid from $zone. Reply "invite" to join.
```

Each message starts with `message:`. Lines you leave out mean "any"; `#` lines are ignored (older exports' `guild:` lines are accepted and ignored). Anything the importer can't read is reported, and the rest still imports.

**Auto-invite** (set up in **Options > Recruiting**): when a player you whispered from this tab replies with one of your up to 5 keywords, Nootropic Guild Manager sends them a guild invite. Keywords match whole words in any case (`join` matches "Join pls" but not "joining"), and can be phrases like `sign me up`. Replies from anyone you didn't whisper here are ignored. Because WoW: Forever only allows guild invites from a click, this shows a one-click **Invite** popup by default (**Ask me first** is on). Untick it on clients that allow fully automatic invites.

**Do Not Whisper list** (on by default, **shared with the guild**, set up in **Options > Recruiting**): when someone you whispered replies with one of up to 5 words or phrases (defaults: `dnw`, `leave me alone`, `do not whisper`, `stop whispering`, `not interested`; whole words, any case), they're added to the list. The list syncs to everyone in the guild running the addon, so once one recruiter is told to stop, nobody in the guild bothers that player again. People on it show "Do not whisper", can't be ticked, whispered or invited, and are skipped by future searches. This check runs before the invite keywords, so "yes, but leave me alone" never invites. **View List** shows who's on it, when and by whom (click a name to take them off for everyone), and right-clicking a player adds or removes them by hand. Additions and removals appear in the Audit tab. Unticking the box stops adding people; anyone already listed stays protected.

Messages and keywords are saved per guild.

**Tags tab** (officers, and ranks the Guild Master lets manage tags) — manage the guild's tags. The list is on the left with each one's count of members; click one to edit it on the right: its name, an **icon** (click the big icon or **Change...** to pick any icon from the game's macro icon menu, **search** them by the names of the spells and items that use them (e.g. "fire bolt", "murloc", "plate"; the first time the picker opens each session it indexes spells and items in the background for a few seconds; hover an icon to see what uses it), or **paste** one found outside the game: its name like `inv_misc_head_murloc_01`, its file number like `134169`, or a Wowhead icon link; a preview shows whether this version of the game has it), a **color** (Quest Gold, Rare Blue, Epic Purple, Horde Red, Legendary Orange, Emerald Dream, Murloc Green, Northrend Ice, Darnassus Rose, Mithril Silver, plus the nine class colors under **Class Colors**) and its order, with a preview. **Save** keeps your changes, **Undo** drops them. The editor also shows who has a tag (**Show in Roster** lists them on the Find tab). **Delete** removes a tag from everyone. **+ New Tag** starts a new one in the same editor. Right-click a row for Move Up, Move Down and Delete. Tags are shared with everyone in the guild running the addon. Ten tags are created to start, each with its own icon: Questing, Dungeons, Raiding, World PvP, Battlegrounds, Crafting, Gathering, Leveling, Roleplay, Social.

Members can tag **themselves** (on their own profile or by right-clicking their own row); only officers can tag other people.

**Audit tab** (officers only) — every synced change across the guild: when, who changed it, which character, and what changed (e.g. "+Raiding", "Marked as an alt of Markpri", "Discord changed"). Search it, filter by kind of change (tags, main/alt, spec, roles, professions, contact, officer log, tag list, tag icons, permissions, Do Not Whisper) or by character, and click a row to open that profile. Changes saved together (within one 15-second batch, see below) are grouped into one line; hover it to see each change, or untick **Group changes**. How long history is kept is set in Options.

## Who can do what

| | Everyone with the addon | Officers |
| --- | --- | --- |
| See roster, tags, mains/alts, specs, professions, contact info | yes | yes |
| Recruit; add to or remove from the Do Not Whisper list | yes (by default) | yes |
| Edit their **own** tags, spec, roles, professions and contact info | yes | yes |
| Tag other guildmates | | yes (by default) |
| Link mains and alts | | yes (by default) |
| Edit others' spec, roles, professions and contact info | | yes (by default) |
| Manage the tag list (Tags tab) | | yes (by default) |
| Officer Log, Change History, Audit tab | | yes |

"Officers" are ranks that can read officer notes (the game's own permission). If someone is promoted or demoted, the addon updates on the spot.

**Permissions** (Guild Master only, in **Options > Officers > Permissions**): every row marked "by default" can be handed to other ranks: **manage the tag list**, **tag other guildmates**, **link mains and alts**, **recruit** (everyone by default), and **edit other guildmates' profiles** (spec, roles, professions, contact). Pick ranks from each row's menu, or the default to go back. Untick everyone and only the Guild Master can. The Guild Master always can. Officer Log and Audit always stay with officers: the game only delivers that data to officer ranks. Permission changes show in the Audit tab.

## Options

Open from **Options > AddOns > Nootropic Guild Manager**, `/ngm options`, shift-clicking the minimap button, or right-clicking the addon compartment entry.

Options has three pages in the game's AddOns list:

- **Nootropic Guild Manager** (main page)
  - **Appearance**: the **addon icon** (Ale Mug, Brewfest Stein or your **Guild Emblem**, shown on the window, the minimap button and the Guild & Communities shortcut; the emblem falls back to the mug outside a guild or without a tabard), **use my guild's name in the window title** (also in the "x using ... Guild Manager" text), **show how many guildmates use the addon** (on by default), the **shortcut on the Guild & Communities window**, **Show tags and alts on the Guild roster** (on by default), and **Learn when I usually play** (on by default).
  - **Minimap Button**: show/hide it, and choose what left-click, right-click and shift-click do (Find, Recruitment, Tags, Audit, Options, show/hide window, or nothing).
  - **Reset**: window size and position, and list columns (roster and recruitment list).
  - **About**: sync stats with a **Sync Now** button, **Open Guild Manager**, and the most useful commands.
- **Recruiting** (saved per guild): the **recruitment whisper button on /who results** (on by default), **Auto-Invite** (invite on a keyword reply, ask me first, up to 5 keywords) and **Do Not Whisper** (on/off, up to 5 words, and the shared list). The Recruitment tab shows how these are set under **Replies**, with a **Reply Settings...** button that opens this page.
- **Officers**: **Permissions** (Guild Master, whole guild) and **Audit History** (keep 30, 60 or 90 days on your copy). Members see this page but can't change it.

The window's tabs run down its right side like the character panel's; hover one for its name. Tabs you can't use (Recruitment without the recruit permission, Tags and Audit for non-officers) are hidden.

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
| `discord:mira` | Discord name or contact note |
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

Every shared value (a member's tags, main, spec, professions, contact info, an officer log entry, a tag definition or icon, a permission) is stored with the time it was changed and who changed it. The newest change always wins, so everyone ends up with the same data no matter the order messages arrive in.

- **Batches:** your changes show up for you instantly but are sent 15 seconds after the first one, all together. Everything in one batch is grouped in the audit.
- **Repair:** every few minutes, and whenever you open the window, each copy of the addon sends a short checksum of its data. If a guildmate's checksums differ, the records that differ are re-sent on the same channel, and other clients skip re-sending what someone just sent. Missed messages, officers who were offline, and new installs all catch up this way, with no "Sync" button needed. Nothing is ever whispered.
- **Officer-only data** (officer log, audit) only ever travels on the game's officer addon channel, which the game delivers only to officer ranks.
- **Pacing:** messages are rate-limited to stay well under the game's limits; if the game reports throttling, messages are retried rather than lost.

In testing, three simulated clients (two officers and a member) with 40-50% of messages randomly dropped, one officer offline while others made changes, and conflicting edits all ended up identical.

`/ngm sync` runs a sync immediately and shows counts of messages sent, received and applied.

## Your data

Everything is saved per guild in `WTF/Account/<account>/SavedVariables/NootropicGuildManager.lua`, along with your settings. **Private notes never leave your computer**; shared data syncs as described above.

What is shared:
- With everyone running the addon: each player's own professions and spec, tags (with their icons and colors), mains/alts, spec/profession overrides, contact info (Discord name and note), roles, when each person usually plays (only the learned summary), the Do Not Whisper list, recruitment statuses (the last 14 days), which addon version each person runs, and the Guild Master's permissions.
- With officers only: Officer Log entries (140 characters max; deleting one deletes it for every officer) and the audit trail.

Guildmates on 1.x use an older sync protocol and don't exchange data with 2.0 at all. When you first load 2.0, data from removed features (reviews, ratings, map dots, polls, stats, goals, kudos, About me, status, pronouns, tab settings) is deleted from your saved data.

A note on trust: the addon checks permissions before sending anything, and officer data can only arrive through the officer channel. A guildmate who modified their copy of the addon could still forge a guild-wide change, but every change is recorded in the Audit tab with its author, so it would be visible to officers.

## Commands

| Command | Does |
| --- | --- |
| `/ngm` | open or close |
| `/ngm find <text>` | open with a search |
| `/ngm recruit` | open the Recruitment tab |
| `/ngm options` | open the options |
| `/ngm diag` | report what the Guild & Communities shortcut, the guild roster hooks and the /who whisper buttons can see, and which name and version the addon uses for you |
| `/ngm sync` | sync now and show sync stats |
| `/ngm audit` | open the Audit tab (officers) |
| `/ngm minimap` | show or hide the minimap button |
| `/ngm reset` | reset the window size and position |

## Code layout

```
NootropicGuildManager.toc
Core/      Core.lua (namespace, events, utils, slash)  Data.lua (classes, specs, professions, tags)  Database.lua (saved data, permissions)  Sync.lua (records, repair, transport)
Services/  Roster.lua (roster, search, sort)  Comm.lua (own spec/professions)  Messages.lua (custom message rules)  Recruit.lua (/who, whisper queue, invites)  Profile.lua (contact, usually online)  Audit.lua (change descriptions)
UI/        Widgets.lua  Columns.lua  ScheduleGrid.lua  BrandIcon.lua  MemberPicker.lua  IconPicker.lua  RosterView.lua (Find tab)  DetailPanel.lua  GuildRoster.lua (hooks on the game's roster)  RecruitView.lua  MessagesView.lua  TagsView.lua  AuditView.lua  MainFrame.lua  MinimapButton.lua  Options.lua  Communities.lua  WhoWhisper.lua
```

## Names in WoW: Forever

Forever characters have a first and second name (e.g. "Audrey Pichhale") and no realms. The addon whispers and invites by the plain name, never "Name-Realm", and shows the two names in separate roster columns.
