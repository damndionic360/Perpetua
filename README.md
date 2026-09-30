# Perpetua

The guild addon for **&lt;Perpetua&gt;**, an Alliance guild on the PvP ruleset for WoW Classic: Forever.
Guildmates' gear, talents, professions, attunements and raid loot, shared over guild chat, plus the profile sync for [perpetua.gg](https://perpetua.gg).

- Install: [CurseForge](https://www.curseforge.com/wow/addons/perpetua) or [perpetua.gg/addon](https://perpetua.gg/addon)
- In game: `/ppta` (or `/perpetua`), or click the crest on the minimap
- What it does: [CURSEFORGE.md](CURSEFORGE.md) · Changes: [CHANGELOG.md](CHANGELOG.md)

## Releasing

Bump `## Version` in `Perpetua/Perpetua.toc`, add a section to `CHANGELOG.md`, and push to `main`.
The Release workflow tags the version, then packages that tag and uploads it to CurseForge and GitHub Releases. Pushes that don't change the version publish nothing. Pushing a tag yourself also releases it.
