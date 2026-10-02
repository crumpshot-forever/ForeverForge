# WO-A — Vendor Stop

| Field | Value |
|-------|-------|
| **Package** | A — Vendor Stop |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/13 |
| **Branch** | `feat/package-a-vendor-stop` |
| **Issue** | #2 |
| **Lane** | `lane:uat` |

## Features under test

- Repair All (merchant button /ff switch)
- Vendor Price Tooltip

## Grok Build steps

1. `git fetch origin && git checkout feat/package-a-vendor-stop && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Merchant: Repair All works; respects money
- [ ] Tooltip shows vendor price on sellable items
- [ ] Both toggles persist across reload
- [ ] No Lua errors at vendor

## Report back (template for Lead chat)

```
UAT A — Vendor Stop: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #13
Ready for Lead to merge? yes/no
```
