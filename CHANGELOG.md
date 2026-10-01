# Changelog

## 1.6.0

Package G — Chat Kit (seven independent chat tools). Lead may rebase after Packages A–F merge; this release is numbered from main `1.0.8`.

- **Chat Copy Button.** A Copy control near chat tabs opens a selectable box of recent chat text for Ctrl+C.
- **Clickable URL Copy.** `http(s)://` and common Discord invite forms become clickable; click opens a copy popup. The browser is never opened.
- **Sticky Channel Control.** Optional sticky whispers (default off) and sticky custom channels (default off).
- **Chat Fade Off.** Disables or greatly extends fade on the default chat frames only.
- **Channel Short Names.** Common labels shorten to tags like `[G]`, `[P]`, `[R]`, `[O]`, `[W]`.
- **Whisper Ding.** A short sound on whisper; optional Battle.net whisper ding (default off).
- **Name Mention Highlight.** Highlights your character name in public chat; optional sound (default off).

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
