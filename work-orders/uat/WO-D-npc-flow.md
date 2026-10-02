# WO-D — NPC Flow

| Field | Value |
|-------|-------|
| **Package** | D — NPC Flow |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/16 |
| **Branch** | `feat/package-d-npc-flow` |
| **Issue** | #5 |
| **Lane** | `lane:uat` |

## Features under test

- NPC Assist (gossip skip ∪ flight direct)
- Quest Auto (accept/turn-in; refuse gold-cost / multi-reward)

## Grok Build steps

1. `git fetch origin && git checkout feat/package-d-npc-flow && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Non-quest gossip auto-continues; Shift overrides
- [ ] Flight master opens taxi as expected
- [ ] Quest Auto accept/turn-in; refuses paid / multi-reward correctly
- [ ] One /ff section; no Lua errors

## Report back (template for Lead chat)

```
UAT D — NPC Flow: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #16
Ready for Lead to merge? yes/no
```
