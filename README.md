# Forever Forge

One menu of light-weight tools for WoW: Forever. Each tool has its own on/off switch. The normal bags, bank, loot window, party frames, and tooltips stay in place.

Current version: **1.3.0**.

Open the menu with the minimap button, or type `/ff`, `/forge`, or `/foreverforge`.

## Install

1. Download this repository and keep the folder named `ForeverForge`.
2. Put `ForeverForge` in `Interface\AddOns`.
3. Restart the game. The menu should show `v1.3.0`.

Do not rename the folder. The game only loads it when the folder name matches `ForeverForge.toc`.

## Tools

- **Clean Bags.** Sections in the combined backpack, with a count on each label.
- **Clean Bank.** The same sections on the bank. Labels stay short so the search box remains usable.
- **Quick Swap.** While the bank is open, move one whole section between your bags and the bank. The hearthstone stays in your bags.
- **Auto-sell junk.** Sell grey junk when a merchant opens. Quest items stay.
- **Repair All.** Repair all gear at a repair merchant. Optional guild funds. Skips non-repair vendors.
- **Ninjee Loot.** Take a corpse at once when auto-loot should run. Bind-on-pickup prompts stay yours to answer.
- **ID Tooltips.** Spell, item, NPC, and quest IDs. A quest item can show the quest name. Optional vendor sell price (unit and stack).
- **SpellMaxer.** A local line when one of your own action-bar spells is a lower rank than you can use.
- **Enemy Player Alert.** A short sound and a local line for an enemy player in nameplate range. A guild name is included when the game provides it. The same character is skipped for 1 minute.
- **Click Heal.** For a Priest, Druid, Paladin, or Shaman, modified clicks on party and raid frames cast heals. Your own character frame is left alone.
- **Mail Expire Alert.** On login, chat if recorded alt mail expires within N days. Snapshots when you close the mailbox.
- **NPC Gossip Skip.** Skips single non-quest gossip and opens the flight map at flight masters. Hold Shift for normal talk.
- **Auto Quest.** Accepts and turns in quests. Hold Shift to handle them yourself. Skips gold-cost and multi-reward turn-ins.

Chat lines from these tools stay in your own chat window and start with `Forever Forge:`.

Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Releases (CurseForge)

Tagged releases (`vX.Y.Z`) are packaged by GitHub Actions and uploaded to CurseForge. Setup and Lead checklist: [docs/release-curseforge.md](docs/release-curseforge.md).

## License

[MIT](LICENSE). Copyright (c) 2026 crumpshot-forever.

## Support

Forever Forge is free, including every future update. If you've enjoyed this addon, please leave a donation and tell your friends. https://ko-fi.com/crumpshot

## Sprint / UAT (Grok Build)

- Live board: https://crumpshot-forever.github.io/ForeverForge/board.html
- Git work-orders (assignment bus): [`work-orders/`](work-orders/) — start at [`ACTIVE.md`](work-orders/ACTIVE.md)
- Build manual: [`docs/grok-build.md`](docs/grok-build.md)
