# WO-B — Quiet Errors

| Field | Value |
|-------|-------|
| **Package** | B — Quiet Errors |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/14 |
| **Branch** | `feat/package-b-quiet-errors` |
| **Issue** | #4 |
| **Lane** | `lane:uat` |

## Features under test

- Curated combat UI error suppress (`Modules/QuietErrors.lua`)

## Grok Build steps

1. `git fetch origin && git checkout feat/package-b-quiet-errors && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Toggle on: known spammy ERR_* quiet in combat
- [ ] Toggle off: errors return
- [ ] Important errors still visible (not over-suppressed)
- [ ] No Lua errors

## Report back (template for Lead chat)

```
UAT B — Quiet Errors: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #14
Ready for Lead to merge? yes/no
```
