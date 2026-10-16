# Sprint board (Build-facing mirror)

**Issues:** label `lane:*` (`ideation`, `approved`, `uat`, `parked`, `released`, `tabled`) shows where each card sits.

**State:** nothing is in UAT right now. Packages B, F and G are built but parked. The Oct 11 ideas are waiting for Product's top-5 cut.

Ship one package at a time → UAT → Lead merges → then next. Do **not** merge from Build. Do **not** tag unless Lead says ship.

## Released

| Item | Notes | Release |
|------|-------|---------|
| A Vendor Stop | Repair All · Vendor Price Tooltip (PR #13, issue #2) | v1.4.0 |
| C Mail Kit | Mail Expire Alert only; Rapid Mail dropped, the game already has Open All (PR #15, issue #3) | v1.4.0 |
| D NPC Flow | NPC Gossip Skip · Auto Quest (PR #16, issue #5) | v1.4.0 |
| E Quick Accept | Accept Summon · Accept Res · Party invites · Decline Duels · BG Auto-Release, all default OFF (PR #17, issue #6) | v1.4.0 |
| Talent Profiles | Save talent builds per character and spec; stage points, never commit (PR #32, issue #31) | v1.5.0 |
| Minimap icon toggle | Menu checkbox and `/ff minimap` (PR #34, issue #33) | v1.5.0 |
| Talent Apply fix | Config Apply and `/ff talents apply` stage the saved build (PR #35) | v1.5.1 |
| Auto-sell junk crash fix | Empty item link no longer errors (PR #39) | v1.5.2 |
| `/tm` fix | Target marks no longer blocked as Forever Forge (PR #40) | v1.5.3 |

Earlier menu tools already shipped: Clean Bags · Clean Bank · Quick Swap · ID Tooltips · SpellMaxer · Auto-sell junk · Turbo Loot · Enemy Player Alert · Click Heal.

## Parked (built, need a rebase onto current main before UAT)

| Pkg | Name | What it does | PR | Issue |
|-----|------|--------------|----|-------|
| B | Quiet Errors | Suppress a curated list of combat UI error spam | [#14](https://github.com/crumpshot-forever/ForeverForge/pull/14) | #4 |
| F | Durability Warning | One chat warning per gear piece at or below a threshold; silent in combat option | [#18](https://github.com/crumpshot-forever/ForeverForge/pull/18) | #7 |
| G | Chat Kit | Copy · URL copy · Sticky channels · Fade off · Short names · Whisper ding · Name mention | [#22](https://github.com/crumpshot-forever/ForeverForge/pull/22) | #21 |

## Ideation (Oct 11 proposals, awaiting Product's top-5 cut)

Scout's own top picks: S1, S2, S6, S7, S3.

| # | Name | What it does |
|---|------|--------------|
| S1 | Bag Space Warning | Chat or sound when free bag slots run low |
| S2 | Quest Item Tooltip | "Quest: X (3/8)" on item tooltips, from your own quest log |
| S3 | Rested XP Readout | Rested amount on XP bar hover and at login |
| S4 | Hearth Info | Hearthstone tooltip shows bind location and time left |
| S5 | Supply Low Warn | Chat when food, water or bandages run low |
| S6 | Block Guild Invites | Auto-decline guild invites and petitions |
| S7 | Solo BoP Confirm | Auto-confirm bind-on-pickup loot when not grouped |
| S8 | Sound Mute Lite | Curated mute list of annoying sound IDs |
| S9 | Ding Shot | Automatic screenshot on level-up |

## Tabled (do not build, not killed)

Coordinates #8 · Zone Level Tooltip #9 · Chat Lite #10 · Trainer Peek #11 · World Buff Expiry #12 · Chat Timestamps (Forever has an in-game option)

## Dropped

Rapid Mail (Open All): the game already has it.

### How to point Build at a package

> "UAT Package **X** from `work-orders/SPRINT.md` — follow `work-orders/uat/WO-*.md`."

Or ask Lead to set `work-orders/ACTIVE.md` and say: "Do ACTIVE."
