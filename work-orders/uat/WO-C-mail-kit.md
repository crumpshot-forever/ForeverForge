# WO-C — Mail Kit

| Field | Value |
|-------|-------|
| **Package** | C — Mail Kit |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/15 |
| **Branch** | `feat/package-c-mail-kit` |
| **Issue** | #3 |
| **Lane** | `lane:uat` |

## Features under test

- Rapid Mail (Open All)
- Mail Expire Alert

## Grok Build steps

1. `git fetch origin && git checkout feat/package-c-mail-kit && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Mailbox: Open All pulls expected mail
- [ ] Expire warn fires when mail near expiry (or test hook documented)
- [ ] Toggles persist
- [ ] No Lua errors at mailbox / login

## Report back (template for Lead chat)

```
UAT C — Mail Kit: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #15
Ready for Lead to merge? yes/no
```
