# Changelog

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
