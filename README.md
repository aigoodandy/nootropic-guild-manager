# Nootropic Guild Manager

A guild roster for **World of Warcraft: Forever** that shows each member's professions and specialization, links alts to their mains, tags what they enjoy, lets officers rate how well they play their class and keep a dated officer log, records an audit trail of every change, and searches all of it. Shared data stays in sync between everyone running the addon.

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

- **Columns** button (or right-click any header) shows or hides columns. Your choice is saved between logins. Name can't be hidden.
- **Rearrange columns** by dragging a header left or right; a gold marker shows where it will land. The order is saved between logins. "Reset column order" in the Columns menu, or **Reset Roster Columns** in Options (order, widths and shown columns), puts things back.
- **Resize a column** by dragging the right edge of its header. Widths are saved; "Reset column widths" in the Columns menu undoes it. The last column fills the leftover space.
- **Smaller windows** shrink columns toward a minimum width, then hide them in this order: Rank, Class, Lvl, Location, Professions, Rating, Main / Alt, Tags, Spec, Second Name. First Name is never hidden. Hidden columns come back when you widen the window, and the Columns menu marks them "(window too narrow)".
- The **Spec** column and the profile show each class's talent-tree icon.

- **Click a member** to open the detail panel beside the roster.
- **Right-click a member** for quick tags, rating and main/alt (officers), whisper and invite.
- **Tags bar** under the search box filters by tags (members must have every selected tag).

**Character profile** (scrolls) — opens beside the roster:

- **Main & Alts** (editing: officers only) — on an alt: shows "Alt of <main>" (click the name to open that profile) with Change Main, Make This Main and Unlink. On a main: lists their alts with an X to unlink each, plus Add Alt and Mark as Alt of. Linking works from either side and both stay in sync. A searchable character picker opens for choosing.
- **Specialization**, **Professions** (add them and set skill levels), **Tags**, and **Rating** (officers only; right-click the stars to clear). Officers can edit anyone; members can edit only their own tags, spec and professions.
- **Private Notes** — only you ever see these; the box grows as you type.
- **Change History** (officers only, at the bottom) — every synced change to this character: who, what and when. "View in Audit tab" opens the full list.
- **Officer Log** — short timestamped entries with the author's name, newest first. Only visible to ranks that can read officer notes, and shared only with other officers running Nootropic Guild Manager.

**Recruitment tab**

1. Set a level range, optionally a class and zone, and click **Search /who** (it runs the game's own `/who` through a secure button, the approved way for addons, so it can't be used in combat). To keep you clear of spam detection, searches are limited to one every 15 seconds and 12 per 5 minutes; the button counts down until the next one is allowed. Everyone without a guild (who isn't already in yours) is added to the list. The game returns at most 50 players per search and limits how often you can search, so use narrow level ranges. Tick **Step levels** and keep clicking Search to sweep through every level.
   - **Guild:** tick it and type a guild name to find members of that guild instead of players without one (for recruiting from other guilds). Matches the name or its beginning; your own guild is never included. Off by default.
2. **Tick the players you want to message** (click the checkbox or anywhere on the row). **Select New** ticks every player nobody in the guild has contacted; **Clear** unticks all. Hover a row to read the message that player will get.
3. Click **Send Whispers (N)**. Whispers go out one at a time, at least 12 seconds apart and no more than 40 per hour, so the game never sees the addon as a spammer. The button shows the countdown and turns into **Stop** while sending. If the game ever refuses an automatic whisper, the addon switches to click-to-send: the button becomes **Send Next** and each click sends one (same pacing).
4. The Status column tracks each player: New, Queued, Whispered, Replied, Invited, and Joined! (detected automatically when they appear in your roster). Contacted players stay in the list so you never message anyone twice; **Clear New** removes only the uncontacted ones and **Hide contacted** filters them out.
   - **Statuses are shared with the guild.** When anyone running the addon whispers, hears back from, or invites a player, everyone else sees it ("Whispered 2 hr ago by Mira") and can't tick that player, so nobody is whispered twice by the same guild. Hover the row to read their reply. Shared statuses are kept for 7 days, then forgotten; your own list keeps your own history.
5. **Invites only after a whisper.** Right-click a player to invite them; the option stays unavailable ("whisper them first") until they've been whispered. Right-click also offers a one-off custom whisper and removing them.

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

**Built-in class messages**: a ready-made, friendly message for each class your faction can play is added for you (turned on, after any messages of your own). Edit them, switch them off or delete them; **Class Defaults** adds back any class that's missing one.

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

**Auto-invite**: when a player you whispered from this tab replies with one of your up to 5 keywords, Nootropic Guild Manager sends them a guild invite. Keywords match whole words in any case (`join` matches "Join pls" but not "joining"), and can be phrases like `sign me up`. Replies from anyone you didn't whisper here are ignored. Because WoW: Forever only allows guild invites from a click, this shows a one-click **Invite** popup by default (**Ask me first** is on). Untick it on clients that allow fully automatic invites.

**Do Not Whisper list** (on by default, **shared with the guild**): when someone you whispered replies with one of up to 5 words or phrases (defaults: `dnw`, `leave me alone`, `do not whisper`, `stop whispering`, `not interested`; whole words, any case), they're added to the list. The list syncs to everyone in the guild running the addon, so once one recruiter is told to stop, nobody in the guild bothers that player again. People on it show "Do not whisper", can't be ticked, whispered or invited, and are skipped by future searches. This check runs before the invite keywords, so "yes, but leave me alone" never invites. **View List** shows who's on it, when and by whom (click a name to take them off for everyone), and right-clicking a player adds or removes them by hand. Additions and removals appear in the Audit tab. Unticking the box stops adding people; anyone already listed stays protected.

Messages and keywords are saved per guild.

**Reviews tab** (the last tab) — anonymous reviews of the guild.

- **Everyone** can rate the guild 1-5 stars and write a message (up to 500 characters), once every 7 days.
- **Only officers** can read reviews. They see the average rating, how many reviews gave each number of stars, and every review from the last year, newest first. Click one to read it and see the officer comments.
- **Officer comments**: officers can comment on a review; other officers see the comment with its author's name. You can delete your own comments, nobody else's.
- **Nobody can change or delete a review**, officers included. Reviews and comments are kept for a year, then deleted.
- **How it stays anonymous**: a review never carries a name. Its id is random, it's dated by day only, and it isn't sent when you click Submit but 2-15 minutes later. It goes to a single officer running the addon (not the whole guild); that officer's copy saves it without a name and shares it with the other officers at low priority on the officer channel. If no officer with the addon is online, it waits (up to 30 days) and is sent when one is.
- **What an addon can't hide**: the game itself attaches the sender's name to every addon message, so the receiving officer's game client briefly knows who sent it. Nootropic Guild Manager discards that name and never saves or shows it, but someone running their own tools to watch addon traffic at that moment could see it. The 7-day limit is remembered by your own copy of the addon (per account and guild), since the guild can't know who wrote what.

**Tags tab** (officers only) — create, rename, recolor, reorder and delete tags. Tags are shared with everyone in the guild running the addon. Click a tag's name to see everyone who has it. Ten tags are created to start: Questing, Dungeons, Raiding, World PvP, Battlegrounds, Crafting, Gathering, Leveling, Roleplay, Social.

**Audit tab** (officers only) — every synced change across the guild: when, who changed it, which character, and what changed (e.g. "Rating changed from ★★ to ★★★" shown as star icons, "+Raiding", "Marked as an alt of Markpri"). Search it, filter by kind of change (tags, rating, main/alt, spec, professions, officer log, tag list) or by character, and click a row to open that profile. Changes saved together (within one 15-second batch, see below) are grouped into one line; hover it to see each change, or untick **Group changes**. How long history is kept is set in Options.

## Who can do what

| | Everyone with the addon | Officers |
| --- | --- | --- |
| See roster, tags, mains/alts, specs, professions | yes | yes |
| Add to or remove from the Do Not Whisper list | yes | yes |
| Share recruitment statuses | yes | yes |
| Write an anonymous guild review (every 7 days) | yes | yes |
| Read reviews, comment on them | | yes |
| Edit their **own** tags, spec and professions | yes | yes |
| Edit anyone's tags, spec, professions, mains/alts | | yes |
| See and edit ratings | | yes |
| Officer Log, Change History, Audit tab, Tags tab | | yes |

"Officers" are ranks that can read officer notes (the game's own permission). If someone is promoted or demoted, the addon updates on the spot.

## Guildmates on the map

Every copy of the addon shares its player's map position with the guild (every 15 seconds while moving, once a minute standing still; never inside dungeons). Guildmates appear on the world map as dots in their class color, on zone and continent maps. Hover a dot for the same details as the roster tooltip; click it to open their profile. The roster's **Location** column shows each guildmate's zone with a small map button that opens the map there and highlights them.

Both are on by default. Options has separate switches to stop sharing your own location and to hide the dots.

**Custom dot colors** (off by default): turn it on in Options to see the colors guildmates picked for their dots, and to pick your own dot color and outline color (with a preview and a **Use Class Color** reset). With it off, every dot is its class color with a black outline. Your colors are shared with the guild and only show for people who turned the option on. Positions are never saved or audited and disappear after 3 minutes without an update.

## Options

Open from **Options > AddOns > Nootropic Guild Manager**, the gear button at the top of the window, `/ngm options`, shift-clicking the minimap button, or right-clicking the addon compartment entry.

- **Addon Icon**: Ale Mug, Brewfest Stein, or your **Guild Emblem**. The choice applies to the window's top-left icon, the minimap button and the Guild & Communities shortcut. The emblem falls back to the mug when you're not in a guild or it has no tabard.
- **Audit History**: keep 30, 60 or 90 days of change history. Older entries are deleted.
- **Minimap Button**: show/hide it, and choose what left-click, right-click and shift-click do (Roster, Recruitment, Tags, Audit, Reviews, Options, show/hide window, or nothing).
- **Guildmate Locations**: share my location; show guildmates on the world map; custom dot colors (your dot and outline color).
- **Use my guild's name in the window title**: "Knights of Azeroth Guild Manager" instead of "Nootropic Guild Manager".
- **Show shortcut on the Guild & Communities window**: a side tab with the addon icon under the window's own tabs.
- **Open Guild Manager**, **Reset Size and Position** and **Reset Roster Columns** buttons.

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
| `-raiding` | exclude a match |

`/ngm find <text>` opens the roster with a search already typed.

## Where professions and specs come from

The game does not let addons read another player's professions or talents. Nootropic Guild Manager handles this two ways:

- **Members running Nootropic Guild Manager** share their own professions and spec automatically over the hidden guild addon channel when they log in, when they change talents or skills, and when someone opens the roster or presses **Sync**. A green check marks synced data.
- **Everyone else** can be filled in by hand from the detail panel. Synced data takes priority for professions; a manual spec always wins over a synced one.

Spec is detected from the modern specialization API when the client has it, otherwise from whichever talent tree has the most points (shown as a split like `5/31/15`).

## Mains and alts rules

- Links always point at the top-level main. Marking a character as an alt of someone's alt links it to that main instead.
- Marking a main (who has alts) as an alt moves their whole family to the new main.
- **Make This Main** swaps roles when a player changes which character they main.

## How syncing works

Every shared value (a member's tags, main, spec, professions, rating, an officer log entry, a tag definition) is stored with the time it was changed and who changed it. The newest change always wins, so everyone ends up with the same data no matter the order messages arrive in.

- **Batches:** your changes show up for you instantly but are sent 15 seconds after the first one, all together. Everything in one batch is grouped in the audit.
- **Repair:** every few minutes, and whenever you open the window, each copy of the addon sends a short checksum of its data. If a guildmate's checksums differ, the records that differ are re-sent on the same channel, and other clients skip re-sending what someone just sent. Missed messages, officers who were offline, and new installs all catch up this way, with no "Sync" button needed. Nothing is ever whispered.
- **Officer-only data** (ratings, officer log, audit) only ever travels on the game's officer addon channel, which the game delivers only to officer ranks.
- **Pacing:** messages are rate-limited to stay well under the game's limits; if the game reports throttling, messages are retried rather than lost.

In testing, three simulated clients (two officers and a member) with 40-50% of messages randomly dropped, one officer offline while others made changes, and conflicting edits all ended up identical.

`/ngm sync` runs a sync immediately and shows counts of messages sent, received and applied.

## Your data

Everything is saved per guild in `WTF/Account/<account>/SavedVariables/NootropicGuildManager.lua`, along with your settings. **Private notes never leave your computer**; shared data syncs as described above.

What is shared:
- With everyone running the addon: each player's own professions and spec, tags, mains/alts, spec/profession overrides, the Do Not Whisper list, and recruitment statuses (the last 7 days), map dot colors, and which addon version each person runs.
- With officers only: guild reviews (anonymous) and officer comments on them, ratings, Officer Log entries (140 characters max; deleting one deletes it for every officer) and the audit trail.

A note on trust: the addon checks permissions before sending anything, and officer data can only arrive through the officer channel. A guildmate who modified their copy of the addon could still forge a guild-wide change, but every change is recorded in the Audit tab with its author, so it would be visible to officers.

## Commands

| Command | Does |
| --- | --- |
| `/ngm` | open or close |
| `/ngm find <text>` | open with a search |
| `/ngm recruit` | open the Recruitment tab |
| `/ngm options` | open the options |
| `/ngm diag` | report what the Guild & Communities shortcut can see |
| `/ngm sync` | sync now and show sync stats |
| `/ngm audit` | open the Audit tab (officers) |
| `/ngm reviews` | open the Reviews tab |
| `/ngm minimap` | show or hide the minimap button |
| `/ngm reset` | reset the window size and position |

## Code layout

```
NootropicGuildManager.toc
Core/      Core.lua (namespace, events, utils, slash)  Data.lua (classes, specs, professions, tags)  Database.lua (saved data)  Sync.lua (records, repair, transport)
Services/  Location.lua (shared positions)  Roster.lua (roster, search, sort)  Comm.lua (own spec/professions)  Recruit.lua (/who, whisper queue, invites)  Messages.lua (custom message rules)  Audit.lua (change descriptions)  Reviews.lua (anonymous guild reviews)
UI/        Widgets.lua  BrandIcon.lua  MemberPicker.lua  RosterView.lua  RecruitView.lua  MessagesView.lua  DetailPanel.lua  TagsView.lua  AuditView.lua  ReviewsView.lua  MainFrame.lua  MinimapButton.lua  MapPins.lua  Options.lua  Communities.lua
```

## Names in WoW: Forever

Forever characters have a first and second name (e.g. "Audrey Pichhale") and no realms. The addon whispers and invites by the plain name, never "Name-Realm", and shows the two names in separate roster columns.
