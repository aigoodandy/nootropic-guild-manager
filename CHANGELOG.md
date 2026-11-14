# Changelog

Every release is on the [releases page](https://github.com/keasbeexd/nootropic-guild-manager/releases) with a `-forever.zip` that WowUp installs. Versions 2.12 and newer sync with each other; older versions use older sync protocols and don't exchange data with them (2.12 still shows their version, so they're told to update).

## 3.0.0

NGM meets your guild's Discord, and looks like it belongs in the game. **3.0 syncs with 2.12**, so guildmates can update at their own pace.

- **NGM Peon, your guild's herald (optional).** NGM Peon is a Discord bot and a dashboard at **ngmpeon.app** that carries word between the game and your guild's Discord: rank roles, events with sign-ups, a guild feed, Social Butterfly from Discord chat and voice, and more. The addon still works entirely on its own; add NGM Peon whenever your Discord should join in.
- **Two codes carry it across.** The Guild Master (or an officer) types `/ngm discord` to make a code for NGM Peon (ranks, rank permissions, mains and alts, Tank / Healer / DPS, when the guild plays, the tabard's colors), and `/ngm peon` to bring NGM Peon's code back into the game (mains, roles, Discord names, champions and events), shared with the whole guild. The dashboard's Sync tab walks you through both, and the Guild Master is reminded after 3 days without a sync.
- **Upcoming Events tab.** The guild's dungeons, raids and nights made on the NGM Peon dashboard: when, how long, who's coming and where to sign up in Discord. Shared with the guild like everything else.
- **Champions from NGM Peon.** When your guild uses NGM Peon, the Hall of Fame's monthly champions come from it (counted from Blizzard's data for everyone), so the game and Discord always agree.
- **The game's own look.** Blizzard's own windows, buttons, side tabs, scroll bars and fonts throughout (every alphabet shows), with the accents (headings, labels, the open tab, bars) in **your guild tabard's colors**, the same as on ngmpeon.app. Any tabard reads well: the colors are brightened or darkened just enough. Without a tabard: herald blue. Messages use the game's own red, green and gray.
- **NGM's banner is the icon**, in your tabard's colors, on the window, the minimap button and the Guild & Communities tab. The icon and theme choices in Options are gone: it's always your guild's.
- **The Guild & Communities tab** sits under Blizzard's own side tabs, spaced and sized like them, wherever they are.
- **Leaner:** the /who and recruiting watchers stop whenever nothing they follow is on screen.
- **Options > About** links to **ngmpeon.app** only: downloads, help, bug reports and NGM Peon.
- **Sharing switches only for what's yours alone:** your recipes and when you usually play. Your spec, professions, statistics and guild chat time are always shared, since they're public anyway (Blizzard's API, inspecting you, guild chat), and everyone online near your level shows in Play Together.

## 2.12.0

Sync, rebuilt from the ground up: lean, stricter, and fast in big guilds. **Everyone in the guild needs 2.12**: older versions don't sync with it (they still see your version, and are told to update).

- **Nothing sent while nothing changes.** No more background checks every few minutes. Changes are sent once, bundled and compressed. When you log in, your copy sends one tiny fingerprint of its data and one guildmate answers: if it matches, that's two short messages and done.
- **Exactly what's missing, from the right person.** If something differs, the two copies narrow it down (32 groups, then the people in the groups that differ), and yours fetches only what it lacks: from each person who wrote it if they're online, otherwise from an officer, with the work spread over the officers online. In a simulated 300-member guild: a login with nothing new costs about 70 bytes, a member back after a few days with 60 changes to fetch is caught up in about 30 seconds, and a brand-new install has everything in about 2 minutes.
- **Members whose guild messages go nowhere.** WoW: Forever sometimes accepts a player's guild addon messages and delivers them to nobody. Their copy now notices within seconds (its own messages never come back) and goes through one online officer: a short hello, an acknowledgement, then their data. The officer passes on only that player's own records.
- **Officers and recruiters follow the game's own rank settings** (Guild Control: **Officer** and **Invite Member**). Change them in the game and the addon follows. Every copy checks each person's current rank, so a demoted or departed officer stops being trusted at once. **Options > Permissions** now only asks what the game doesn't: who may link mains and alts, edit their own profile, and edit guildmates' profiles (the separate Recruit permission is gone).
- **A simpler tooltip, the same everywhere** (the addon's lists, Play Together, and the game's guild roster): the game's own header (name, rank, level, race and class, zone), then main or alt (and whose), spec, role, the two main professions, Discord, their addon version (or, without the addon, whether they've been reminded to install it), and your private note. Usually online and the rest are on the profile.
- **Only guild and officer messages are read** (plus, on officers' copies, those whispers from guildmates). Party, raid and other whispers are ignored.
- **Sync at a glance:** a dot next to the version number in the window: green in sync, yellow working on it, grey nobody online to compare with, red a problem. Hover for details, click to check now. `/ngm sync` shows the same, and `/ngm diag` is shorter.
- Your own records come back on a new install (your usual play hours and Hall of Fame history, from guildmates who have them).
- **Your guild's tabard is the addon's icon** (window, minimap button, the Guild & Communities tab; the Options header and About page keep the addon's own medallion), and the Nootropic medallion the only other choice in Options, and what's shown outside a guild or without a tabard. Everyone moves to the tabard once; pick the medallion again in Options if you prefer it. The Ale Mug and Brewfest Stein icons are gone.
- The tabard looks right at small sizes: the minimap button, the Guild & Communities tab and the Options previews show the guild's emblem on its own background color, with one ring (the button's or tab's own), instead of stray pieces of the game's guild portrait art.
- **A player's main and alts share what's about the player:** their Discord name (all their characters show the one set most recently on any of them; edit it on any and it changes for all), when they usually play (all their characters' hours together), and the addon version (the newest seen on any of them: an alt shows its main's and the other way round; unlink an alt and it shows its own again). Professions, recipes, raid readiness, spec and roles stay with each character.
- The contact note is gone from profiles (only the Discord name is kept).
- **Find:** alts always sort right under their main, whatever the sort (a family goes where its first character sorts), and are tagged "alt" just left of the online icon. The game's guild roster no longer gets an "alt" tag on its rows (its tooltip already says main or alt). A new **Last Online** column ("Online", or how long ago) sorts by who's online.
- **Who Can Craft?** shows each recipe with the icon of what it makes (WoW: Forever gives many crafting spells a placeholder icon), and drops the "green: online now" legend.
- The minimap button's icon sits centered in its ring, with no gap under it (laid out the way WoW: Forever's own minimap buttons are).
- The window is always titled "Nootropic Guild Manager" (the option to use your guild's name is gone).

## 2.11.0

- **New sync, simpler and stricter.** Every copy now checks, per author, the time of their newest record and a checksum over all of them, and asks for exactly that author's records since a time when something differs. A member's check names only themselves (a few dozen characters); officers' checks name everyone, since they pass everyone's data on. The old group checksums, record lists and re-send markers are gone.
- **Members whose guild messages go nowhere.** Rarely, the game accepts someone's guild addon messages but delivers them to nobody, while their whispers still get through. Every guild message normally comes back to its sender, so a copy that hears none of its own back now whispers them to an online officer (2.11 or later), who passes on that member's own records, and only theirs. `/ngm sync` shows whether your guild channel works and who you're sending through.
- **Officers recognised by rank.** Members can't see the officer channel, so they couldn't tell who the officers were, and refused data officers passed on, Hall of Fame champions officers recorded, and install reminders officers sent. The Guild Master's copy now records which ranks are officer ranks (only the Guild Master can), and every copy checks that against the roster.
- **Tighter intake.** Only guild and officer addon messages are read, plus whispers from guildmates to an officer passing their data on. Party, raid and other whispered messages are ignored.
- `/ngm sync <name>` shows what has arrived from that guildmate this session, which shard you and they are on, and how their messages arrive. `/ngm sync` also counts every addon message heard and any that couldn't be read, with the reason.
- Older copies still receive live changes from 2.11 and send theirs, but they no longer repair gaps with it: everyone should update.

## 2.10.1

- Fix: a player with more than one character sharing a first name (say "Mykkie Sickyy" and "Mykkie Frost") could have the addon think they were playing the other one. Everything they sent was then signed with the wrong character's name, and guildmates rightly refused it: their version never showed, and none of their data arrived. The addon now picks the character that's online with your class and level.
- `/ngm sync <name>` shows what has arrived from that guildmate this session: how many messages of each kind, when the last one came, and how many of their records were applied, already known, or refused.
- `/ngm sync` also shows how much of the queue is your own data versus data being passed on, and how often the game held messages back.

## 2.10.0

- Leaner sync. When two copies find their data differs, they now swap a compact list of what each has in the differing parts, and send each other only the records that are actually missing or out of date, instead of re-sending everything in those parts. Catching up after time offline is much faster and uses far less of the game's addon-message allowance.
- Recruitment statuses (the hundreds of "whispered / invited / declined" entries) now sync in their own lane, only between members whose rank may recruit. Everyone else no longer stores or exchanges them, so their own data isn't held up behind them.
- Big records (recipe lists, for example) are sent compressed with the game's own compression, once everyone online with the addon is on 2.10 or later.
- Works with older copies: while anyone online still runs 2.9 or earlier, the old way is used with them.

## 2.9.3

- Fix: a new member's data (version, professions, Hall of Fame…) could take ages to reach anyone, or never seem to. When copies compare data, every copy also passed on every recruitment status and Do Not Whisper entry it knew (600+ in our guild), queuing hundreds of messages, and the member's own records waited behind them. Now a member passes on only their own records, first; officers still pass on everything. The same record is also never queued twice while it's waiting to go out.

## 2.9.2

- Fix: changing someone's rank in the game's guild window could be blocked ("NootropicGuildManager has been blocked from an action only available to the Blizzard UI"). The addon's alt labels on that roster were added in a way that left Blizzard's row data marked as touched by an addon, and the rank dropdown reads that data. They're now added the way Blizzard intends (after their code, without touching it).
- The "alt" label on the game's guild roster sits at the right edge of the name column on every row, with a dark backing, instead of sometimes landing in the Rank column.
- The /who whisper buttons no longer read protected text on screen (it filled the game's error log on every search).
- Opening Options during combat says to wait, instead of being blocked by the game.
- `/ngm sync` also shows how many records from guildmates were refused this session, and the last one with the reason (who sent it, which record, why), to track down a guildmate whose data never shows up.

## 2.9.1

- Fix: some guildmates showed version **"old"** even on the latest version. At login the game first gives only your first name, and the addon announced your version under it ("Deja" instead of "Deja Rollupz"), which guildmates rightly refuse. It now waits until the roster gives your full name, and re-sends your version once every session, so one lost at a quick /reload is fixed at the next login.
- A guildmate whose version hasn't arrived yet now shows a grey **?** instead of a red "old".

## 2.9.0

- **Champion titles:** last month's Hall of Fame champions carry their title all month, in gold on their profile and in tooltips (Find, Play Together and the game's guild roster): "November's Champion: Quests completed, Kills". A person's alts show their main's titles.
- **Champions are crowned on the 2nd** of each month (a day for everyone's numbers to arrive), by the first officer's copy online. The Hall of Fame shows when: "Next champions crowned Tuesday 1 December, 7 pm (in 12 days)" in your own time. On the 1st it says the points are being tallied and when the champions will be crowned, and each card's "Last month" line reads "tallying..." until then. Cards always show the officially crowned champions, so they match the titles. The officer whose addon crowns them gets a chat message saying the winners can now be announced.
- **Recount:** for one day after crowning (until 00:00 UTC on the 3rd), late numbers can still change a winner, for someone whose last session hadn't reached anyone yet. A category only changes when someone has caught up with or passed the crowned number, so an officer whose copy is missing numbers can never undo a correction. The officer whose copy corrects it gets a chat message with what changed, and the Announce button's tooltip notes the champions changed since the last announcement. After the recount day, the month is final.
- **Announce Champions** (officers, top of the Hall of Fame tab): one click posts last month's champions to guild chat, split into lines if needed. Hover first to see exactly what will be posted and who announced them last.
- **Checking Hall of Fame numbers:** when an officer inspects a guildmate, their copy quietly compares the guildmate's real game statistics (the game's statistics comparison) with what the guildmate's addon shares. Officers see the result in that person's tooltip: "match the game", or which numbers are higher than the game says. Nothing happens automatically; an officer can **Hide from Hall of Fame**. Each guildmate is checked at most every 6 hours, only when you inspect them.
- **Security review fixes:** line breaks and other control characters in data from other copies of the addon are now stripped, as for your own edits (they could fake extra lines in tooltips); batch ids from other copies must be the addon's own short ids; Hall of Fame check results travel only on the officer channel, so other members never receive them; Announce Champions only names current guildmates. The Announce tooltip now says when the champions were corrected after anyone's announcement: "Corrected 2 Dec by Marc, AFTER Shawn last announced on 2 Dec".
- The minimap button no longer shows two rings: the medallion's own gold ring is trimmed there, so the minimap's border is the only one. (Other icon styles and the window portrait are unchanged.)

## 2.8.2

- On the Find tab, **(missing)** in the Addon Version column is a button (blue) while someone can be reminded: one click whispers them the install reminder, and it turns into a grey **(reminded)**. Hover it first to see the exact whisper. Offline members show a grey (missing), since whispers need them online.

## 2.8.1

- **Remind to install** shows the exact whisper (with their name filled in) when you hover the button on a profile or the right-click menu entry.
- The reminder text is now edited in a multi-line box under **Options > Install Reminder**, saved as you type, with a length counter (whispers top out at 255 characters) and a **Default Text** button. Add your Discord invite to it if you'd like the reminder to cover that too.

## 2.8.0

- **Social Butterfly** on the Hall of Fame: hours spent in guild chat conversations. The day is split into 15-minute blocks; a block counts when you and at least one guildmate both spoke in it, at most 8 blocks a day, so ten messages in a row count once and talking to yourself counts for nothing. Only the time is shared, never what was said (part of **Share my statistics**).
- **Champions:** each Hall of Fame card shows last month's champion at the bottom. Winner takes all; a tie makes everyone at the top a champion.
- **Most Champion Wins**, a new card: titles won, all time and by month. Titles are written down by an officer's copy of the addon on the 3rd of each month (once everyone's numbers have arrived), so nobody can award themselves one.
- **Mains and alts always count as one person** on every Hall of Fame card and for champions: their numbers (and Social Butterfly hours) add up. The Hall of Fame's "Count alts" box is gone (Overview keeps its own).
- **Harder to cheat:** the game only lets an addon read its own player's statistics, so an edited copy could lie about its own numbers. Every statistic now has a generous ceiling (per day of play since WoW: Forever opened, and per month), a month can never beat all time, and anyone whose shared numbers break a limit is left out of the Hall of Fame. Officers can also **Hide from Hall of Fame** (right-click on Find) anyone whose numbers look wrong; it's shared and audited.
- Install reminders can only be sent in your own name and only about guildmates (an edited copy could otherwise have blocked reminders for the whole guild).

## 2.7.3

- **Remind to install:** guildmates without the addon show **(missing)** in the Addon Version column. Right-click them on Find, on the game's guild roster, or use the button on their profile, to send a one-click whisper saying why the addon is worth having and where to get it. Shared with the whole guild: each person is reminded at most once per 30 days, and the column then shows **(reminded)** with who did it. Edit the text in **Options > Install Reminder Text** (`$first`, `$name` and `$guild` are filled in). Search `is:missing` lists everyone without the addon.
- **Hall of Fame:** a line under the totals shows how many guildmates aren't on the board yet (no addon), with a button that lists them.
- **Discord names** show with an @ (`@keasbeexd`), whether or not you typed one, and copying gives the plain name. Profiles with a Discord name get an **On Discord** badge.

## 2.7.2

- **Fix: syncing between guildmates on different server shards.** WoW: Forever quietly tags every name with the shard the player lives on (for example `-CAMWOWUS1Realm2PvP` for one guildmate and `-CAMWOWUS2Realm2PvP` for another), so each copy of the addon filed the same person under a different name. Shared data did arrive, but landed on a name that wasn't on the roster: guildmates didn't show as using the addon, their spec, hours and Hall of Fame numbers were missing, and some of their changes were refused. Names are now stored without the tag, data from older copies is tidied as it arrives, and your saved data is tidied once when you log in (duplicates merged, the newer record kept, private notes combined).
- **Everyone should update.** 2.7.2 reads data from older versions, but older versions can't read what 2.7.2 sends.
- Fix: the recruitment whisper button (the envelope) could appear on the Guild & Communities roster, on your own row, after a /who search that included you. It now stays on the /who list, and never shows for you or a guildmate.

## 2.7.1

- Overview: the counts and percentages next to each bar no longer run into the bar.
- Play Together: the level and how far it is from yours (for example "Level 21 (-6)") is no longer cut off.
- README and addon pages now have in-game screenshots of every tab.

## 2.7.0

- **Overview tab** for everyone: how many of each class, level band and profession, and **When we play**, a week heatmap of how many guildmates usually play in each two-hour block (from the hours they share; hover for who). Click a bar to list those members on Find. Counts members online in the last 7, 30 or 90 days, or everyone; each person once as their main unless **Count alts** is on. `/ngm overview`.
- **Hall of Fame tab** for everyone: guild leaderboards from the game's own character statistics, the top five for quests, kills, dungeon and raid bosses, dungeons entered, honorable kills, battlegrounds and duels won, epics looted, deaths (and from falling), flights, hearthstones, fish and hugs, with guild totals. All time, this month or last month; alts added up under their main unless **Count alts** is on. Each member's addon shares their own numbers, never gold; **Share my statistics** in Options > Sharing turns it off and clears them. `/ngm hof`.

## 2.6.3

- Fix: the close button (X) did nothing in combat on every window: Who Can Craft?, profiles, the main window, Do Not Whisper, custom messages, the Invite prompt, the member picker and the welcome tour. They close straight away now. (Escape already worked.)

## 2.6.2

- Fix: whispers stuck needing **Send Next** for every one. If the game blocked a single automatic whisper, the addon switched to click-to-send and saved that for good. It now lasts only until a `/reload` or your next login, and updating to 2.6.2 switches everyone back to automatic. `/ngm diag` shows whether whispers are automatic and, if the game blocked one, what and when.

## 2.6.1

- The Find tab's **Sort** button is gone again; sort by clicking a column header.
- **Every column is shown by default** except Second Name: Level, Class, Location, Rank and Addon Version now start on, so you can sort by level or rank straight away. If you never changed your columns, they switch over once; if you did, yours are kept (Options > Reset > List Columns, or right-click a header > Show all, gets the new default).
- The Version column is now called **Addon Version**.

## 2.6.0

- A Sort menu on the Find tab (removed again in 2.6.1).

## 2.5.3

- The first release uploaded to CurseForge and Wago (2.5.2 only reached GitHub). No changes in game.

## 2.5.2

- Now on **CurseForge** (https://www.curseforge.com/wow/addons/nootropic-guild-manager) and **Wago Addons** (https://addons.wago.io/addons/nootropic-guild-manager), as well as GitHub. Every release goes to all three, so install from whichever app you use; WowUp finds it on any of them.

## 2.5.1

- **Sync limits**: a guildmate's copy can't flood everyone's saved data: values are capped at 4,000 bytes, recipe lists need a real profession ID (at most 12 per member), and a non-officer can add at most 500 new records per 10 minutes.
- Releases are now published automatically (GitHub today; CurseForge and Wago once their projects exist). See docs/PUBLISHING.md.

## 2.5.0

- **Welcome tour** on first launch (and once for everyone updating): a page per tab, your sharing choices, your profile basics (Discord, contact note, roles), and for the Guild Master the permissions. Reopen it from Options or `/ngm welcome`.
- **Sharing options** (Options > Sharing): Share my spec and professions, Share my recipes, Learn when I usually play, and Show me in Play Together. Turning one off stops sharing it and clears what was already shared; hiding from Play Together is respected by everyone's copy.
- Fix: when someone stops sharing their spec and professions, guildmates' copies drop them right away instead of after a reload.

## 2.4.0

- **Who Can Craft?** Every recipe your guildmates know, searchable, with online crafters first. Recipes are shared automatically when someone with the addon opens one of their profession windows (only recipes they've learned, never someone else's linked list). Open it from the Find tab's **Who Can Craft?** button or `/ngm craft <name>`. Each profile's professions show a **Recipes** button.
- **Raids tab on profiles.** Raid readiness worked out by each member's own addon: the Onyxia attunement (Drakefire Amulet, from quest 6602 Horde / 6502 Alliance or the amulet itself) and the Brooch of the Wardens for The Barrow Deeps' prison. The Barrow Deeps and Hyjal Summit need no attunement.
- **About page** in Options: what the addon does, credits, and links to the maintainer's site, the Nootropic Discord and the GitHub page.
- **New icon**: the Nootropic Medallion, the addon's own artwork (also the logo on GitHub), is now the icon on the window, the minimap button, the Guild & Communities shortcut and the AddOns list. The game's Ale Mug and Brewfest Stein icons and your guild emblem are still choices in Options.
- A **How It Works** introduction at the top of Options.
- Documentation: in-game introductions, this changelog, `docs/ARCHITECTURE.md`, and an offline test suite in `tests/`.

## 2.3.0

- **Play Together** tab for everyone: guildmates online near your level (your zone first) and guildmates who usually play at this hour. `/ngm play`.

## 2.2.1

- The **Recruit** permission defaults to officers (guilds that already picked ranks keep their choice).
- New **Edit their own profile** permission, everyone by default.

## 2.2.0 — first public release

- **Sync checks the sender.** A shared record only counts if the player who sent it may make that change; only officers may pass on other people's records; permission settings only count from the current Guild Master. Before this, any guildmate could forge someone's profile or the Guild Master's permissions with a hand-made addon message.
- Escape codes in shared text are defused; oversized chunked messages are refused.
- Taking someone off the Do Not Whisper list needs the Recruit permission (anyone can still add).
- Cleanup of code left from removed features.

## 2.1.10

- Guild invites by copy and paste: the Invite prompt shows `/ginvite First Last` to copy (Ctrl+C), then Enter, Ctrl+V, Enter. WoW: Forever blocks every invite that comes from an addon, including `/ginvite` put in the chat box by one.

## 2.1.9

- Whispers read like a person typed them: first name (new `$first` token), "I'm recruiting for...", and a question instead of "Just reply invite". `yeah` joined the invite keywords.

## 2.1.8

- Invite tried putting `/ginvite` in the chat box (still blocked; see 2.1.10).

## 2.1.7

- The secure Invite button stays above the visible one (it could slip underneath and miss clicks). Invite added to `/ngm diag`.

## 2.1.6

- Invites through a secure `/ginvite` button, replacing the popup that called the blocked invite function (still blocked on Forever; see 2.1.10).

## 2.1.5

- Built-in class messages rewritten in the default message's voice.

## 2.1.4

- **Do Not Whisper window** (`/ngm dnw`): the permanent list plus everyone whispered in the last 14 days, with the time left.
- **Add to Do Not Whisper** on the right-click menu of names in chat and on unit frames.
- Whispers per hour is a setting (40 by default).

## 2.1.3

- Whispers fit WoW's 255-character limit with Forever's two-part names: a shorter default message, first name only when needed, never cut mid-word. Editors show the longest a message can get.
- `no` joined the Do Not Whisper words, and only answers to the addon's own whisper can put someone on the list.

## 2.1.2

- Options text and checkbox hints wrap instead of overlapping or running off the page. Settings left over from tags cleared.

## 2.1.1

- Options page text overlap fixed; new default recruitment message.

## 2.1

- **Roster change log** in the Audit tab: joins (with who invited), rejoins, leaves, kicks, promotions and demotions from the guild event log, plus level-ups, note changes and name changes from the roster. Join dates and "rank since" on profiles.
- Tags removed. New sync protocol (5).

## 2.0

- Launch release for WoW: Forever, slimmed down from aigoodandy's 1.x: guild reviews, ratings, map sharing, polls/stats/goals, kudos, About me/status/pronouns, the compact roster, the recruiting bar, roster export and tab customization removed. Hybrid with the game's Guild & Communities roster. Guild Master permissions. MIT licence.
