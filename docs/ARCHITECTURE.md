# How Nootropic Guild Manager works

A guide for anyone reading or changing the code. For using the addon, see the [README](../README.md).

## Layout

The addon is plain Lua and Blizzard frames, no libraries. Files load in the order of `NootropicGuildManager.toc`; every file starts with a comment saying what it does.

| Folder | What's in it |
| --- | --- |
| `Core/` | `Core.lua` (namespace, events, helpers, slash commands, start-up), `Data.lua` (classes, specs, professions, roles, recruiting defaults, raid readiness checks, About links), `Database.lua` (saved data, settings, permissions), `Records.lua` (shared records: types, who may write what, limits, newest wins, working data), `Sync.lua` (carrying records between guildmates in game: checks, requests, bundles, relays, transport) |
| `Services/` | Logic with no windows: `Roster.lua` (guild roster, search, sort), `Comm.lua` (your own spec and professions), `Profile.lua` (Discord name and usual play hours, both shared by a player's main and alts), `Recruit.lua` (/who, whispers, lockouts, Do Not Whisper, invites), `Messages.lua` (custom recruitment messages), `Audit.lua` (audit text), `RosterLog.lua` (joins, leaves, promotions from the guild event log and roster), `Recipes.lua` (shared recipes), `Readiness.lua` (raid attunements and keys), `HallOfFame.lua` (your character statistics for the leaderboards), `Sharing.lua` (what you share: switches that stop and clear your shared data) |
| `UI/` | Windows and hooks: `MainFrame.lua` (the window and its tabs), `RosterView.lua` (Find), `TogetherView.lua` (Play Together), `OverviewView.lua` (Overview: census and play-time heatmap), `HallOfFameView.lua` (Hall of Fame leaderboards), `RecruitView.lua` + `MessagesView.lua` (Recruitment), `AuditView.lua`, `DetailPanel.lua` (profiles), `RecipesView.lua` (Who Can Craft?), `DNWView.lua` (Do Not Whisper window and name menus), `InvitePrompt.lua`, `Options.lua`, `Welcome.lua` (first-launch tour), `GuildRoster.lua` + `Communities.lua` (hooks on the game's Guild & Communities window), `WhoWhisper.lua` (button on the game's /who results), `MinimapButton.lua`, and shared pieces (`Widgets.lua`, `Columns.lua`, `ScheduleGrid.lua`, `BrandIcon.lua`, `MemberPicker.lua`) |
| `docs/` | This file |
| `tests/` | Offline tests that run the real files against stand-ins for the game (see [Testing](#testing)) |

Modules hang off the addon namespace (`ns.Sync`, `ns.Roster`, `ns.DB`...). `ADDON_LOADED` sets up saved data (`ns.DB:Init`); `PLAYER_LOGIN` starts everything else (see the end of `Core/Core.lua`). Modules talk through `ns:Fire(event)` / `ns:On(event, fn)` (e.g. `ROSTER_UPDATED`, `MEMBER_CHANGED`, `RECIPES_CHANGED`, `AUDIT_CHANGED`).

## Saved data

`NootropicGuildManagerDB` (account-wide):

- `settings` — your options (minimap, window size, columns, whispers per hour, Play Together range...).
- `guilds["<Guild>-<Realm>"]` — one entry per guild:
  - `sync.guild` / `sync.officer` — the shared records (below). Everything shared lives here.
  - `members[full]` — working data built from the records, plus `note`, your private note, which is never shared.
  - `recruit` — your recruiting setup (messages, keywords, the players you found).
  - `rosterSnap` — the last roster seen, to notice level-ups, note and name changes.

## Sync

Everything the guild shares is a **record**: `key -> { v = value, t = server time, a = author, b = batch }`. The newest version of a record wins (ties broken by author, then value), so every copy ends up the same whatever order changes arrive in.

The code is in two layers:

- **`Core/Records.lua`** is the data and its rules: record types, who may write what, limits, newest-wins, and turning records into the addon's working data. It knows nothing about how records travel.
- **`Core/Sync.lua`** carries records between guildmates in game. It calls `S:Apply(key, rec, ctx)` for whatever arrives, and Records calls `S:Broadcast(key, rec)` for each change to send.

Any other way of carrying records (NGM Peon in 3.0) plugs in at the same two points, with the same rules: see [NGM Peon (3.0)](#ngm-peon-30).

Records go with `C_ChatInfo.SendAddonMessage` under the prefix `NootropicGM` on the **GUILD** channel, or **OFFICER** for officer-only data. Only those two channels are read, plus whispers to an officer from a guildmate whose guild channel doesn't deliver (below). Party, raid and other whispers are ignored.

### Lanes

| Lane | Channel | Records | Who takes part |
| --- | --- | --- | --- |
| guild | GUILD | guild records except recruitment statuses | everyone |
| recruit | GUILD | recruitment statuses (`RS`) | members whose rank may recruit (others don't keep them) |
| officer | OFFICER | officer records | officers |

### Messages (protocol 6)

All messages start with the protocol number; other numbers are ignored, except that a 2.11-or-older copy's version record (protocol 5) is read so it shows. Fields are tab-separated.

| Kind | Fields | Meaning |
| --- | --- | --- |
| `R` | key, time, author, batch, value | one record |
| `B` | lane, `z`, data | several records: `Base64(Deflate(lines))`, one `key time author batch value` per line |
| `F` | lane, root, `q` or `a`, target, [32 group sums] | a check: `q` asks, `a` answers (with the group sums when the roots differ) |
| `E` | lane, target, `1` or `2`, groups, `author:newest:sum,...` | per-author lists for the groups that differ (`1` is answered with `2`) |
| `Q` | lane, target, `author:since,...` | "send these authors' records newer than `since`" (`0`: all) |
| `H` / `K` | | relay hello and its acknowledgement (whispers) |
| `C` | id, part, parts, data | a piece of a message longer than 250 bytes (at most 16 parts) |

Numbers are base 36.

### How it flows

- **Changes** are sent once: Records batches a player's changes for 15 seconds, then Sync bundles them per lane, compressed when that's smaller. Nothing is re-sent on a timer: **with no changes and nobody logging in, nothing is sent.**
- **At login** (and on `/ngm sync`, Sync Now, or a click on the status dot) a copy sends `F q` per lane with one **root** fingerprint. One guildmate answers, the same one on every copy: candidates are ordered by a mixed hash of asker and name, officers first in the guild lane; the first answers after 0.5 s, the next after 3.5 s if nobody has, up to 4. If the roots match, that's the end: two short messages.
- **If they differ**, the answer carries 32 **group** fingerprints (authors by name hash). The asker sends its per-author entries (`E 1`) for the groups that differ, the answerer replies with its own (`E 2`), and each side asks (`Q`) for exactly the authors it's behind on. An author's fingerprint is their newest record's time plus the sum of hashes of all their records in the lane. When the other side's newest is later, it asks for records newer than its own newest; when the newest times match but the sums don't (an older record was lost), it asks for all of them (then not again for that author for 15 minutes).
- **Who's asked:** the author, when online (everyone answers for their own records); otherwise an online guildmate whose copies we'd accept (an officer, or anyone in the recruit and officer lanes), chosen per author by the same mixed hash, so the work spreads over the officers online. If a request goes unanswered, the next one goes to someone else.
- **Answers** go to the whole lane channel in compressed bundles, your own records first and recipe lists last, so everyone else who was missing them gets them too. A record already waiting to go out isn't queued again. A copy answers each requester at most 20 times a minute, and not at all while 3,000 messages are already queued.
- **After catching up**, the asker checks once more when data has stopped arriving (up to 5 times a session), and its status says so.

### A guild channel that doesn't deliver

On WoW: Forever the game sometimes accepts a player's guild addon messages and delivers them to nobody (themselves included), while their whispers arrive. Every guild addon message normally comes back to its sender, so a copy that hears nothing back within 8 seconds of its first guild message:

1. picks an online officer (the same ordering as above) and whispers a tiny hello (`H`), since the first whisper to someone can be lost;
2. sends its version and checks again, now as whispers to that officer; checks also still go on the guild channel, and if one ever comes back, it switches back;
3. if no acknowledgement (`K`) arrives within 10 seconds, tries the next officer.

The officer treats those whispers as guild messages from that player, answers their checks itself, passes on their requests to whoever they're meant for, and passes on **only records the player wrote** (never officer records) to the guild. Officers read at most 120 whispers a minute from one guildmate, and only from people on the roster.

### Status

`S:Health()` and `S:StatusLines()` give the state per lane (`checking`, `comparing`, `catching`, `synced`, `alone`), whether the guild channel delivers and through whom, the officer ranks, and session counts. `/ngm sync`, Options and the dot next to the version number in the window show them.

### Record types

| Key | Value | Scope | Who may write it |
| --- | --- | --- | --- |
| `M:<member>` | their main ("" = a main) | guild | ranks with the **links** permission |
| `MS:<member>` | spec override | guild | the member (**own profile** permission) or ranks with **profiles** |
| `RL:<member>` | roles: `tank,healer,damage` | guild | same as `MS` |
| `MP:<member>` | manual professions | guild | same as `MS` |
| `CN:<member>` | `discord;` (the note after `;` is no longer used) | guild | same as `MS` |
| `P:<member>` | spec and professions their addon read | guild | the member only |
| `AV:<member>` | addon version | guild | the member only |
| `SC:<member>` | usual play hours (168 bits as hex) | guild | the member only |
| `RP:<member>:<professionID>` | `profession;id,id,...` (base-36 recipe spell IDs) | guild | the member only |
| `RR:<member>` | completed readiness checks (`ony,brooch`, or `-`) | guild | the member only |
| `HF:<member>` | `1;month;all time;this month;last month id;last month` (each `key=n,...`; month as `202611`, UTC) | guild | the member only |

Hall of Fame extras (Services/HallOfFame.lua): `social` is a count of 15-minute guild chat blocks (you and someone else spoke; 8 a day max), tracked from `CHAT_MSG_GUILD` per character in `Settings().hof[character].social`. Champion titles (`champs`) are never self-reported: officers' copies write `HW:<month>` from `HF:Champions` and every copy counts those. `HF.Plausible` drops records whose numbers beat a per-statistic daily rate since launch (all time), 31 days of it (a month), or all time (a month).
| `HX:<member>` | left out of the Hall of Fame (`1`, or empty = shown) | guild | officers |
| `HW:<month>` | that month's champions, `quests=Name,Name;kills=Name` (written once, from the 2nd of the next month) | guild | officers |
| `HA:<month>` | that month's champions were announced in guild chat (the time; author = who announced) | guild | officers |
| `HC:<member>` | Hall of Fame numbers checked against the game on inspect: `<time>;ok` or `<time>;bad;key=claimed/real,...` | officer | officers |
| `IR:<member>` | when they were reminded to install the addon (the time; the record's author is who reminded them; kept 30 days) | guild | anyone in the guild |
| `PS:<member>` | sharing choices others must respect (`together` = leave me out of Play Together) | guild | the member only |
| `DN:<player>` | `time;what they said` ("" = removed) | guild | anyone adds; removing needs **recruit** |
| `RS:<player>` | `whispered;replied;invited;reply` (kept 14 days) | guild | anyone in the guild |
| `GS:<name>` | guild setting, e.g. `GS:perm_links = "1,3"` | guild | officers; `perm_*` and `officers` only the Guild Master |
| `L:<member>:<id>` | officer log entry | officer | officers |
| `A:<id>` | audit entry | officer | officers (written locally from changes, or by the roster log) |
| `JN:<member>` | `time;inviter` (joined) | officer | officers |
| `RK:<member>` | `time;rank;by` (rank since) | officer | officers |

### Security

A record's author is only what the sender claims; the sender is the one name the game vouches for. So every copy checks each incoming record (`S:Accept` and `S:SenderAllowed` in `Core/Records.lua`):

- The author must be allowed to write the record (their own data, their rank's permissions from the guild roster, or officer), and must be the sender, unless the sender is a **known officer** passing on someone else's record.
- **Officers and recruiters follow the game's rank settings** (Guild Control: **Officer**, flag 22, and **Invite Member**, flag 5, as `Blizzard_GuildControlUI` lays them out). For yourself: `C_GuildInfo.IsGuildOfficer()` and `CanGuildInvite()`. For others: `C_GuildInfo.GuildControlGetRankFlags(rank + 1)` when the game answers (at least one setting on); otherwise `GS:officers` / `GS:recruiters` (rank names), which the current Guild Master's copy writes from those same settings (at login and on `GUILD_RANKS_UPDATE`). Also anyone seen on the officer channel this session, while their rank is still what it was then. Always by **current** rank, so a demoted or departed officer stops being trusted at once. With nothing known yet (a new install, the Guild Master offline), the rank just below the Guild Master counts as officers. `/ngm diag` says whether the game gives other ranks' settings.
- Permission settings (`GS:perm_*`), `GS:officers` and `GS:recruiters` only count when their author is the current Guild Master. The Guild Master's permission choices are only these three: link mains and alts, edit their own profile, edit other guildmates' profiles.
- "Self-only" records (`P`, `AV`, `SC`, `RP`, `RR`, `PS`, `HF`) must be authored by the member they're about.
- Records on the officer channel come only from officers, by the game's rules.
- Keys or authors containing `|` are dropped and `|` and control characters in values are replaced, so shared text can't inject textures, colors, links or extra lines. Messages in pieces are capped (16 parts, 8 unfinished per sender, no pieces inside pieces); a bundle unpacks to at most 64 KB and 1,000 records.
- Limits on what one guildmate can add (`S:WithinLimits`): values up to 4,000 bytes; recipe lists only under numeric profession IDs and at most 12 per member; and at most 500 new records per 10 minutes from any non-officer sender. Officers are exempt, since catching someone up legitimately carries hundreds of records.

Your private notes never leave your computer. Officer data goes only over the officer channel.

## WoW: Forever restrictions worth knowing

- **Guild invites from addons are blocked**, in every form: `C_GuildInfo.Invite`, `/ginvite` from a secure macro button, and `/ginvite` put in the chat box by the addon (opening the chat box from addon code taints it). Only `/ginvite` the player types or pastes works, so the Invite prompt shows the command to copy. **Don't open the chat box from addon code**: it would also taint the player's own `/ginvite` for the rest of the session.
- `/who` must run from a hardware event: the Search button is a secure macro button (`W.SecureOverlay`) placed over the visible one.
- Names have two parts and no realms in chat: whisper and invite by `ns.ChatName(full)`.
- The game still tags names with the server shard each player lives on (`Name-CAMWOWUS2Realm2PvP`), different for different guildmates and left off for your own shard. Since 2.7.2 every name is stored plain (`ns.NormalizeName` drops the tag when `ns.NO_REALMS`), records from older copies are tidied on arrival (`Sync.Canon`), and saved data from before is tidied once (`Sync:CanonicalizeSaved`, `DB:AdoptShardGuilds`).
- Whispers are capped at 255 bytes: `RC:Format` uses first names and cuts at whole words when needed.
- `C_Calendar.AddEvent` is restricted; reading the calendar is fine.
- The window templates' close button calls `HideUIPanel`, which does nothing in combat. Every window calls `W.CombatSafeClose(f)` right after it's created so its X hides it directly.
- Addons can't read other players' quests, bags or recipes: each member's own addon reports theirs (`P`, `RP`, `RR`).

## Adding a shared record type

1. Add it to `S.TYPES` in `Core/Records.lua` with its scope and who may write it (`selfOnly`, `self`, `officer`, `anyone`, or a permission in `DB.PERM_BY_TYPE`). The security checks follow from these.
2. If its key has more than a member (like `L:` or `RP:`), teach `S.ParseKey` where the member name is.
3. Turn the value into working data in `S:Materialize` (or read it straight from the store, as `Recipes.lua` does).
4. Describe it in the comment at the top of `Core/Records.lua` and in the table above.
5. Records of a type that's later removed are deleted on load by `S:PurgeUnknown`. If old clients would fight over the change, bump `PROTO` in `Core/Sync.lua`.
6. Heavy records that can wait (like recipe lists) go in `HEAVY` in `Core/Sync.lua`, so they're sent after everything else.

## Testing

`tests/run.sh` runs every test with LuaJIT (or `lua5.1`). The tests load the real addon files with stand-ins for the game's API and check sync permissions against forged messages, the roster change log, recruitment message lengths and Do Not Whisper rules, the Invite prompt, Play Together, recipes and raid readiness.

`tests/sim.lua` simulates a guild for sync: every member runs their own copy of `Records.lua` and `Sync.lua` against one clock, one roster and a stand-in for the game that delivers addon messages with a delay (and can leave a player's guild channel delivering nothing). `test_sync.lua` covers the protocol and its security in a small guild; `test_sync_scale.lua` measures a 300-member guild at the real send budget (compression is a stand-in at 35%). They don't replace trying it in the game: anything about frames, layout or Blizzard's restrictions needs an in-game check.

## NGM Peon (3.0)

NGM Peon is NGM's Discord bot and website (ngmpeon.app), coming in 3.0. Its server, called "the Hub" below, will hold the same records under the same rules. To keep that simple:

- **Records are the contract.** Keys, values, `t`/`a`/`b`, newest-wins and who may write what are defined once, in `Core/Records.lua`, and documented above. The Hub implements the same rules rather than its own.
- **Two seams.** In game, Sync calls `S:Apply` for what arrives and Records calls `S:Broadcast` for what changes. Anything that carries records between the addon and the Hub uses the same two calls, with `ctx.origin` naming where a record came from.
- **Fingerprints are portable.** Per-author fingerprints (newest time and a sum of record hashes, `S:AuthorSums`) let any two holders of records, a copy of the addon and the Hub included, find what the other lacks without sending everything.
- **Identity** is the character's plain name (Forever has no realms), checked against the guild roster, the same thing the Hub will see.
- **Codes carry records for now.** Addons can't reach the internet, so in 3.0 records travel by copy and paste. `/ngm discord` makes the Guild Master's update code (NGM2, `Services/DiscordCode.lua`): rank names and permissions, the M and RL records changed since NGM Peon last had them, and the When we play counts. It's pasted on the dashboard's Ranks tab. NGM Peon applies the same newest-wins rule, plus one of its own: a member's characters proven theirs by Battle.net can't be linked to someone else's. `/ngm discord setup` makes the short NGM1 code for `/ngm-guild setup` in Discord. The other way, the dashboard's Sync tab, step 1 (NGMP1) is pasted with `/ngm peon`: records set in NGM Peon, taken as if the player pasting had passed them on in guild sync (same rules), then shared with the guild; it also says what NGM Peon already has, so the next `/ngm discord` only carries changes since then (less a week, for records that reach the Guild Master's game late) and sends the When we play grid only when it changed. **Champions:** a guild using NGM Peon gets its Hall of Fame champions from NGM Peon (crowned from Blizzard's numbers for everyone): its code carries each month's `HW` record and `GS:peon` = `1`, and once that's in, no officer's game crowns or recounts on its own, so the game and Discord never name different winners. A desktop connector can carry the same records automatically later.

## Look

The addon looks like the game's own windows: Blizzard's frames, buttons, tick boxes, scroll bars and side tabs, and the game's own fonts (so every alphabet shows, and no fonts are shipped). `UI/Theme.lua` only colours the accents: headings, labels, highlighted words (`ns.GOLD`), the open tab's glow and the bars. The **Theme** setting (Options > Appearance): *Guild* (the default) takes the guild tabard's colours (`Core/Accent.lua`, the same as NGM Peon's dashboard); *Nootropic* is Blizzard's own gold. New UI uses the `NGMFont*` objects (they wrap the game's `GameFont*`), `ns.Theme.C`/`HEX` for accent colours, and `ns.Theme:Paint`/`Ink`/... for anything drawn in a theme colour, so a theme change repaints it.

## Releasing

Push a version tag; the Release workflow tests, packages and uploads it to GitHub (and CurseForge and Wago once they're set up). The steps and the one-time site setup are in [PUBLISHING.md](PUBLISHING.md).
