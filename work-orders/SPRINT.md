# Sprint board (Build-facing mirror)

**Live UI:** https://crumpshot-forever.github.io/ForeverForge/board.html  
**Issues:** label `lane:uat` = ready for Jase + Grok Build UAT.

**Launch:** **`v1.4.0`** shipped 2026-10-02 (CT) — Packages A + C + D + E + launch menu (PR #29).  
**Not in launch:** B Quiet Errors · F Durability · G Chat Kit (still open).

Ship one package at a time → UAT → Lead merges → then next. Do **not** merge from Build. Do **not** tag unless Lead says ship.

| Pkg | Name | Features | PR | Branch | Issue | Lane |
|-----|------|----------|----|--------|-------|------|
| A | Vendor Stop | Repair All · Vendor Price Tooltip | [#13](https://github.com/crumpshot-forever/ForeverForge/pull/13) merged | `main` | #2 | **Released** (`v1.4.0`) |
| B | Quiet Errors | Quiet Errors | [#14](https://github.com/crumpshot-forever/ForeverForge/pull/14) | `feat/package-b-quiet-errors` | #4 | UAT (rebase onto post-launch main) |
| C | Mail Kit | Mail Expire Alert (Rapid Mail dropped — stock Open All) | [#15](https://github.com/crumpshot-forever/ForeverForge/pull/15) merged | `main` | #3 | **Released** (`v1.4.0`) |
| D | NPC Flow | NPC Gossip Skip · Auto Quest | [#16](https://github.com/crumpshot-forever/ForeverForge/pull/16) merged | `main` | #5 | **Released** (`v1.4.0`) |
| E | Quick Accept | Accept Summon · Accept Res · Party invites · Decline Duels · BG Auto-Release (all default OFF) | [#17](https://github.com/crumpshot-forever/ForeverForge/pull/17) merged | `main` | #6 | **Released** (`v1.4.0`) |
| F | Durability | Durability Warning | [#18](https://github.com/crumpshot-forever/ForeverForge/pull/18) | `feat/package-f-durability` | #7 | UAT |
| G | Chat Kit | Copy · URL · Sticky · Fade · Short names · Whisper ding · Mention | [#22](https://github.com/crumpshot-forever/ForeverForge/pull/22) | `feat/package-g-chat-kit` | #21 | UAT |

### Tabled (do not build)

Coords #8 · Zone Level #9 · Chat Lite #10 · Trainer Peek #11 · World Buff #12 · Chat Timestamps (in-game)

### How to point Build at a package

> “UAT Package **X** from `work-orders/SPRINT.md` — follow `work-orders/uat/WO-*.md`.”

Or set/ask Lead to set `work-orders/ACTIVE.md` and say: “Do ACTIVE.”
