# WO-E — Social Convenience

| Field | Value |
|-------|-------|
| **Package** | E — Social |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/17 |
| **Branch** | `feat/package-e-social` |
| **Issue** | #6 |
| **Lane** | `lane:uat` |

## Features under test

- Accept Summon · Accept Res · Decline Duels · BG Auto-Release
- **Defaults: all OFF**

## Grok Build steps

1. `git fetch origin && git checkout feat/package-e-social && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] All four default OFF on fresh SV
- [ ] Each switch works when enabled (summon/res/duel/BG)
- [ ] No surprise auto-accept when OFF
- [ ] No Lua errors

## Report back (template for Lead chat)

```
UAT E — Social: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #17
Ready for Lead to merge? yes/no
```
