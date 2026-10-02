# Sprint board (Build-facing mirror)

**Live UI:** https://crumpshot-forever.github.io/ForeverForge/board.html  
**Issues:** label `lane:uat` = ready for Jase + Grok Build UAT.

Ship one package at a time → UAT → Lead merges → then next. Do **not** merge from Build.

| Pkg | Name | Features | PR | Branch | Issue | Lane |
|-----|------|----------|----|--------|-------|------|
| A | Vendor Stop | Repair All · Vendor Price Tooltip | [#13](https://github.com/crumpshot-forever/ForeverForge/pull/13) merged | `main` | #2 | **Released** |
| B | Quiet Errors | Quiet Errors | [#14](https://github.com/crumpshot-forever/ForeverForge/pull/14) | `feat/package-b-quiet-errors` | #4 | UAT |
| C | Mail Kit | Rapid Mail · Mail Expire Alert | [#15](https://github.com/crumpshot-forever/ForeverForge/pull/15) | `feat/package-c-mail-kit` | #3 | UAT |
| D | NPC Flow | NPC Gossip Skip · Auto Quest | [#16](https://github.com/crumpshot-forever/ForeverForge/pull/16) merged · **v1.3.0** | `main` | #5 | **Released** |
| E | Social | Social Convenience (all default OFF) | [#17](https://github.com/crumpshot-forever/ForeverForge/pull/17) | `feat/package-e-social` | #6 | UAT |
| F | Durability | Durability Warning | [#18](https://github.com/crumpshot-forever/ForeverForge/pull/18) | `feat/package-f-durability` | #7 | UAT |
| G | Chat Kit | Copy · URL · Sticky · Fade · Short names · Whisper ding · Mention | [#22](https://github.com/crumpshot-forever/ForeverForge/pull/22) | `feat/package-g-chat-kit` | #21 | UAT |

### Tabled (do not build)

Coords #8 · Zone Level #9 · Chat Lite #10 · Trainer Peek #11 · World Buff #12 · Chat Timestamps (in-game)

### How to point Build at a package

> “UAT Package **X** from `work-orders/SPRINT.md` — follow `work-orders/uat/WO-*.md`.”

Or set/ask Lead to set `work-orders/ACTIVE.md` and say: “Do ACTIVE.”
