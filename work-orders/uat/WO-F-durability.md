# WO-F — Durability Warning

| Field | Value |
|-------|-------|
| **Package** | F — Durability |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/18 |
| **Branch** | `feat/package-f-durability` |
| **Issue** | #7 |
| **Lane** | `lane:uat` |

## Features under test

- Chat once-per-piece at ≤threshold (default 30%)
- Silence in combat; optional sound default OFF; no OSD

## Grok Build steps

1. `git fetch origin && git checkout feat/package-f-durability && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Warning fires once per piece at threshold
- [ ] Silent in combat when that option is on
- [ ] Sound stays OFF by default
- [ ] No OSD / no Lua errors

## Report back (template for Lead chat)

```
UAT F — Durability: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #18
Ready for Lead to merge? yes/no
```
