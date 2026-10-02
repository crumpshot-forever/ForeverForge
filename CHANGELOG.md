# Changelog

## 1.4.0

- **Quick Accept.** Opt-in Accept Summon, Accept Res, auto-accept party invites, Decline Duels, and BG Auto-Release (all off by default).

## 1.3.0

- **NPC Gossip Skip.** Skips single non-quest gossip and opens the flight map at flight masters. Hold Shift for normal talk.
- **Auto Quest.** Accepts and turns in quests. Hold Shift to handle them yourself. Skips gold-cost quests and multi-reward turn-ins.

## 1.2.0

- **Mail Expire Alert.** On login, chat if any recorded character has mailbox mail expiring within N days (default 3, configurable). Snapshots earliest expiry when the mailbox closes. Multi-alt via name-realm keys.

## 1.1.0

- **Repair All.** Repairs all gear when you open a repair merchant. Optional guild bank funds via Configure. Skips vendors that cannot repair. Does not change the merchant or bag UI.
- **Vendor price on ID Tooltips.** Item tooltips can show unit and stack vendor sell price. Toggle under ID Tooltips → Configure → Vendor price (on by default).

## 1.0.8


- No feature changes. This release checks that CurseForge receives a new tag on its own.

## 1.0.7

- Quest items that you collect, such as Bristleback Quilboar Tusks, show the quest name on the item tooltip.

## 1.0.6

- The menu footer points to the Forever Forge page and no longer shows the feature count.

## 1.0.5

- Quick Swap uses the Forever Forge anvil icon.

## 1.0.4

- Quick Swap uses two crossing arrows instead of the handshake icon.

## 1.0.3

- The minimap button is smaller, in line with a standard minimap icon.

## 1.0.2

- The minimap button is the Forever Forge anvil icon.

## 1.0.1

The installed addon is Forever Forge.

- The folder name is `ForeverForge`, matching `ForeverForge.toc`.
- The menu title and chat prefix are Forever Forge.
- Slash commands are `/ff`, `/forge`, and `/foreverforge`.

## 1.0.0

First public release. Same tools as the 0.9.5 private build.

- Clean Bags and Clean Bank sort those windows into labeled sections. Consumables covers food, potions, elixirs, and scrolls. Category labels stay short.
- Quick Swap moves one section between bags and bank while the bank is open. The hearthstone stays in your bags.
- Auto-sell junk sells grey items at a merchant and keeps quest items.
- Ninjee Loot takes a corpse at once when auto-loot should run.
- ID Tooltips adds spell, item, NPC, and quest IDs, and can show the quest name on a quest item.
- SpellMaxer warns locally when one of your own action-bar spells is a lower rank than you can use.
- Enemy Player Alert plays a short sound and posts a local line for an enemy player in nameplate range, with a guild name when the game provides it. The same character is skipped for 1 minute.
- Click Heal lets a Priest, Druid, Paladin, or Shaman cast from party and raid frames. Your own character frame is left alone.

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

Open the menu with the minimap wrench or `/ff`.
