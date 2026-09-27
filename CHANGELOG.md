# Changelog

Forever Toolkit versions use X.Y.Z.

- X stays 0 until the first public package, then becomes 1.
- Y goes up by 1 for a new tool, and Z returns to 0.
- Z goes up by 1 for a fix or small change.
- The game client stays on the Interface line in `ForeverToolkit.toc`. It is not part of this number.

The first public package will be **1.0.0**. It will be this 0.9.5 feature set, tagged and uploaded from GitHub. Nothing below is a public release yet.

## 0.9.5

- Enemy Player Alert lists every enemy in range. The 10-name cap is gone.
- The same character can be announced again after 1 minute.
- A guild name is added in angle brackets when the game provides it: `Crump Crump <Guild Name> - 20 human mage detected!`

## 0.9.4

- Enemy Player Alert no longer errors while zoning when a player name is hidden. Hidden names are skipped instead of compared.

## 0.9.3

- Quick Swap no longer crashes on a bag-to-bank move while checking item names. The hearthstone still stays in your bags.

## 0.9.2

- Clean Bags category labels match Clean Bank. Each label is only as wide as its title, and never more than half the row.

## 0.9.1

- Food, potions, elixirs, and scrolls sort into Consumables, after Quest Items and before Reagents.
- Quick Swap never sends the hearthstone to the bank.
- Clean Bank category labels no longer cover the search box.

## 0.9.0

Private baseline. Nine tools, each with its own switch in one menu.

- **Clean Bags.** Sections in the combined backpack, with counts.
- **Clean Bank.** The same sections on the bank.
- **Quick Swap.** Move one section between bags and bank while the bank is open.
- **Auto-sell junk.** Sell grey junk when a merchant opens. Quest items stay.
- **Ninjee Loot.** Take a corpse at once when auto-loot should run.
- **ID Tooltips.** Spell, item, NPC, and quest IDs. Quest items can show the quest name.
- **SpellMaxer.** A local line when one of your own action-bar spells is a lower rank than you can use.
- **Enemy Player Alert.** A short sound and a local line for an enemy player in nameplate range.
- **Click Heal.** Modified clicks cast from party and raid frames for a Priest, Druid, Paladin, or Shaman. Your character frame is left alone.

Open the menu with the minimap wrench or `/ftk`.
