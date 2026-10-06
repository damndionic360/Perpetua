# Changelog

## 2.10.0

### New: recipe totals
- Track two or more recipes and the **Profession** list in the objective tracker gets one more block at the bottom, under a thin gold line, **Totals: All Tracked Recipes**: every reagent they need between them, with how many you have, ticked off like the rest once you've got enough.

### Levels on perpetua.gg stay current
- The addon now saves the guild roster too (everyone's level and class, and when they were last online), and the Perpetua app takes it to the site. A character who levelled while nobody else with the addon was on now shows their new level on the site anyway, and in the addon window too.

## 2.9.1

### Fixes
- Hide Olympus didn't hide any chat in 2.9.0: it learned Olympus players but its chat filters never took effect. They're now set up at login through the current chat API, as other addons on this client do.

### Changes
- The Hide Olympus page shows running totals under the number of Olympus players known: messages hidden, invites turned down and trades cancelled. They're kept between sessions.
- Olympus players are saved in a much smaller form, and the list is capped at 5,000: past that, the ones seen longest ago make room.
- `/ppta olympus debug` shows what the chat filters have seen since login.

## 2.9.0

### New: Hide Olympus
- A **Hide Olympus** switch above **Sync now** hides players in any guild with "Olympus" in its name. It starts off.
- Click the words **Hide Olympus** to choose what it does. All of these are on until you untick them:
  - Hide their chat: say, yell, emotes, every channel, and party and raid chat.
    - Hide any chat that says "Olympus", from anyone (like trade asking for an Olympus layer).
  - Hide their whispers, plus any whisper that says "Olympus", from anyone.
  - Turn down their guild invites, and Olympus guild charters.
  - Turn down their group invites.
  - Cancel trades with them.
  - Turn down their duels.
- Optionally, a line in chat whenever an invite, trade or duel is turned away.
- Nothing goes on your ignore list and they can't tell. Switch it off and everything shows again.
- The game only shows someone's guild when you see them (nameplates, mouseover, target, your group, trades, invites and /who), so the addon remembers each Olympus player it spots. A whisper from an Olympus player standing nearby is hidden too, and so is anyone who whispers you about Olympus, from then on. Other chat from someone it hasn't seen yet still shows. **Look them up** on the Hide Olympus page runs a /who for Olympus players, 50 per click.
- `/ppta olympus` opens the page; `/ppta olympus on` and `/ppta olympus off` flip the switch.

### Update notice
- When a guildmate has a newer version of the addon, you'll see **Update available** in the window's sidebar and in the minimap button's tooltip, plus one line in chat per new version.
- The addon's version now shows under **Sync now**.

### Fixes
- Update notices never showed: versions 2.8.2 to 2.8.4 told guildmates they were 2.8.1. The addon now reads its version from its own files.

## 2.8.4

### Fixes
- Joining the guild while logged in now shares your character with guildmates straight away. Before, the addon could save your character before the game had the guild's name, file it in the wrong place, and then quietly send nothing until you restarted the game.

## 2.8.3

### Fixes
- The **Setup** page's three cards (What the addon does, Why link your characters, How to link) now always show their full text. They were coming out too short, so the text ran over the next card and past the bottom of the window. The text is also a little shorter so all three fit.
- The Setup page no longer mentions the guild forums, which are switched off for now.

## 2.8.2

### Fixes
- The **Welcome** page's three cards (Who we are, We're recruiting, About this addon) now always show their full text. They were coming out too short, so the text ran over the next card.

## 2.8.1

### Changes
- The **Forums** tab is switched off for now, along with `/ppta forums`. The addon no longer passes forum posts around the guild. The forums will come back when they open to members on perpetua.gg.

### Fixes
- The **Welcome** page (on characters outside the guild) no longer runs off the bottom of the window. The cards are shorter, and if they ever don't fit they scroll instead.

## 2.8.0

### Members only
- The addon now only works on characters in **<Perpetua>**. On any other character it opens a **Welcome** page instead of the usual tabs:
  - **Who we are:** an Alliance guild on the PvP ruleset for WoW Classic: Forever, and a community that has been gaming together for over eight years.
  - **We're recruiting:** how to apply, with the address for perpetua.gg/apply ready to copy.
  - **About this addon:** what it does for members, and why it needs you to be in the guild.
  - A status box showing which guild the character is in. Horde characters are told they'll need an Alliance character to join.
- Outside the guild the addon sends nothing, listens to nothing and records no loot or rolls.
- Characters outside the guild get one line in chat at login about the guild and `/ppta`.
- Joining the guild unlocks everything straight away, even with the window open, and takes new members to the Setup page.

### Fixes
- Removed a leftover test file from the download. The addon never loaded it.
