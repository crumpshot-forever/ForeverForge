# Forever Forge

Forever Forge is one addon with a set of light-weight tools for WoW: Forever. Each tool has its own on/off switch. Turning one off leaves the others alone. Your settings are remembered.

The tools sit on the normal bags, bank, loot window, party frames, and tooltips. They do not replace those screens.

Open the menu with the minimap button, or type `/ff`, `/forge`, or `/foreverforge`.

Install the folder named `ForeverForge`. Do not rename that folder. The menu title is Forever Forge, and chat lines start with `Forever Forge:`.

Chat lines from these tools stay in your own chat window. They are not sent to say, party, or guild chat.

## Clean Bags

Clean Bags sorts the combined backpack into labeled sections. Each label includes a count, such as Quest Items (12).

The order is:

1. Quest Items
2. Consumables, for food, potions, elixirs, scrolls, and other items the game already calls consumable
3. Reagents
4. Crafting
5. One section for each saved equipment set, named Equipment Set: and the set name
6. Gear, for weapons and armor that are not already in a saved set
7. General
8. Junk, for poor-quality items, after General
9. Empty

The layout appears when you open the backpack. The item buttons stay the normal ones. Section labels are only as wide as the title, and never more than half the row.

Clean Bags runs when the combined backpack is on. Turning the tool off puts the normal combined grid back.

## Clean Bank

Clean Bank uses the same sections, in the same order, on the bank window that is open. It has its own switch. It does not change the backpack.

Category labels stay short and do not take clicks, so the bank search box stays usable.

## Quick Swap

While the bank is open, each Clean Bags and Clean Bank section gets the Forever Forge button to the left of its name.

- On a bag section, the button moves that section into the bank.
- On a bank section, the button moves that section into your bags.

Empty slots have no button. Closing the bank hides the buttons and stops a move that is still running. Items move one at a time.

The hearthstone is never sent to the bank. It stays in your bags.

Quick Swap needs Clean Bags or Clean Bank turned on, because the button lives on those section labels.

## Auto-sell junk

When you open a merchant, Auto-sell junk sells poor-quality grey items one at a time.

Quest items are kept. Items with no sell price are kept. Closing the merchant window stops the selling. Turning the tool off stops it as well.

## Turbo Loot

Turbo Loot takes every item on a corpse at once when auto-loot should run, instead of one click per item.

- If auto-loot is on, opening loot takes the corpse. Hold the auto-loot key and that corpse stays a normal window.
- If auto-loot is off, the window stays manual. Hold the auto-loot key and that corpse is taken immediately.

A second corpse opened a moment too soon is taken as soon as the game will accept it. Bind-on-pickup questions are left for you to answer. Turbo Loot does not change your auto-loot setting.

## ID Tooltips

ID Tooltips adds a short line to the tooltip under your cursor.

- Spells show a spell ID.
- Items show an item ID.
- NPCs show an NPC ID.
- Quests show a quest ID.
- Buffs and debuffs show the spell ID in the aura tooltip.

A quest item in your bags or bank can also show the quest name, such as `Quest: Echeyakee` or `Quest: Consumed by Hatred`, when that item belongs to a quest in your log. Usable quest items and items the quest asks you to collect are both covered. Chat links and merchant items that are not tied to a quest stay unchanged. A hidden ID or title is skipped. Turning ID Tooltips off removes these lines.

## SpellMaxer

SpellMaxer looks at your own action bars. If a button is using a lower rank than the best rank your character can cast, you get one local line:

`Hey, <name>, you aren't Spellmaxing to the MAX! You're using a lower level of <spell>! Check yoself!`

It checks when you log in or reload, when you enter an area, and when your group changes. It checks your bars only. It does not judge other players' classes.

## Enemy Player Alert

When an enemy player comes into nameplate range, you hear a short sound and get one local line:

`Forever Forge: Crump Crump <Guild Name> - 20 human mage detected!`

The guild name is included in angle brackets when the game provides it. If there is no guild, or the name is hidden, the brackets are left off.

The same character is not announced again for 1 minute. Every enemy in range can be listed. There is no cap.

Enemy nameplates must already be turned on in the game. Forever Forge does not change that setting, and it does not detect players farther out than those nameplates.

## Click Heal

Click Heal is for a Priest, Druid, Paladin, or Shaman. Other classes get one local note and no extra clicks.

Modified clicks on party and raid frames cast your heals, cleanses, and resurrection. The spells are attached before combat, so they keep working in a fight. A member who joins during combat is picked up when combat ends.

Your own character frame is not covered. Right-click there still opens the normal menu, including leaving the party.

By default, left click still targets and right click still opens the unit menu. The settings page can turn those into heals. Target and focus frames are off unless you turn that on.

Open Configure on Click Heal to see the spell each click will cast. The name on the right of a row is the current spell. To change it, type the spell you want into the box and press Enter. Leave the box empty to keep the spell on the right. Type `none` and press Enter to turn that click off. Alt-Right is available and starts unused.

The same binding list appears on the party or raid frame tooltip.

## What stays normal

- Bags, the bank, and party frames stay the normal windows.
- Public chat is never used.
- Bind-on-pickup prompts are never clicked for you.
- Friendly health is not drawn on a separate bar. Click Heal uses the frames already on screen.
- The install folder for this build is `ForeverForge`.

Source and changelog: https://github.com/crumpshot-forever/ForeverForge

License: MIT

Forever Forge is free, including every future update. If you've enjoyed this addon, please leave a donation and tell your friends. https://ko-fi.com/crumpshot
