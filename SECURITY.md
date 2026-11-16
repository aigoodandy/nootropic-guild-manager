# Security policy

This covers the NGM Addon and NGM Peon (the Discord bot and ngmpeon.app,
whose code isn't public). NGM Desktop has its own:
https://github.com/keasbeexd/ngm-desktop/security/policy

## Reporting a vulnerability

Please report privately, not in a public issue or pull request:

- Use GitHub's **Report a vulnerability** button on the Security tab of
  this repository (private vulnerability reporting):
  https://github.com/keasbeexd/nootropic-guild-manager/security/advisories/new

Include what you found, how to reproduce it, and which version you tested. A
proof of concept helps; please test only with your own characters, your own
guild and your own Discord server.

You can expect an acknowledgement within a week. Fixes for confirmed issues
are released as soon as they are ready, with an advisory that credits you
unless you ask not to be named.

## What counts

**The NGM Addon** shares records between guildmates' copies; every copy
checks each record against the guild roster and the rank settings. Examples:

- getting other copies to accept a record you may not write (someone else's
  profile, mains and alts, an officer-only or Guild Master setting, a Hall of
  Fame champion), or one in someone else's name;
- data a player switched off (recipes, play hours) reaching anyone else;
- a chat line, whisper, addon message or pasted code that runs anything,
  breaks the game's protected actions (taint), or brings in more than the
  rules allow (`/ngm peon`, NGM Desktop's codes).

**NGM Peon** holds guild and member data and a bot in many Discord servers.
Examples:

- seeing or changing another guild's or another member's data, or a manager
  setting without being a manager;
- getting past the Battle.net checks (setup, ranks, linking, step 2) or the
  dashboard's sign-in;
- anything about NGM Desktop's device keys or API (`/api/app`) beyond what
  your own key may do;
- making the bot post, ping or change roles where it shouldn't.

## Supported versions

Only the newest release of the NGM Addon, and NGM Peon as it runs at
ngmpeon.app, get security fixes.
