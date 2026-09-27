# Forever Toolkit

One menu of small tools for WoW: Forever. Each tool has its own on/off switch. The normal bags, bank, loot window, party frames, and tooltips stay in place.

Current version: **0.9.5**. The first public package will be **1.0.0**.

Open the menu with the minimap wrench, or type `/ftk`.

## Install

1. Download this repository and keep the folder named `ForeverToolkit`.
2. Put that folder in `Interface\AddOns`.
3. Restart the game. The toolkit window should show `v0.9.5`.

Do not rename the folder. The game only loads it as `ForeverToolkit`.

## Tools

- **Clean Bags.** Sections in the combined backpack, with a count on each label.
- **Clean Bank.** The same sections on the bank. Labels stay short so the search box remains usable.
- **Quick Swap.** While the bank is open, move one whole section between your bags and the bank. The hearthstone stays in your bags.
- **Auto-sell junk.** Sell grey junk when a merchant opens. Quest items stay.
- **Ninjee Loot.** Take a corpse at once when auto-loot should run. Bind-on-pickup prompts stay yours to answer.
- **ID Tooltips.** Spell, item, NPC, and quest IDs. A quest item can show the quest name.
- **SpellMaxer.** A local line when one of your own action-bar spells is a lower rank than you can use.
- **Enemy Player Alert.** A short sound and a local line for an enemy player in nameplate range. A guild name is included when the game provides it. The same character is skipped for 1 minute.
- **Click Heal.** For a Priest, Druid, Paladin, or Shaman, modified clicks on party and raid frames cast heals. Your own character frame is left alone.

Chat lines from these tools stay in your own chat window and start with `Forever Toolkit:`.

## Version

`X.Y.Z`

- `X` stays 0 until the first public package, then becomes 1.
- `Y` goes up by 1 for a new tool, and `Z` returns to 0.
- `Z` goes up by 1 for a fix or small change.

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE). Copyright (c) 2026 crumpshot-forever.
