# WO-G — Chat Kit

| Field | Value |
|-------|-------|
| **Package** | G — Chat Kit |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/22 |
| **Branch** | `feat/package-g-chat-kit` |
| **Issue** | #21 |
| **Lane** | `lane:uat` |

## Features under test

- Chat Copy · URL Copy · Sticky Channel · Fade Off · Short Names · Whisper Ding · Name Mention Highlight
- **Not in scope:** timestamps (in-game), Chat Lite (tabled)

## Grok Build steps

1. `git fetch origin && git checkout feat/package-g-chat-kit && git pull`
2. Install this checkout into the WoW Forever `Interface/AddOns/ForeverForge` folder (replace prior build).
3. `/reload` in-game; confirm module toggles under `/ff`.
4. Run the checklist below with Jase.
5. If you fix bugs: commit on this branch, push, open/update the same PR. **Do not merge.**
6. Give Jase a short pass/fail + fix summary to paste into **FF Founding Lead** chat.

## UAT checklist

- [ ] Copy button / URL copy work
- [ ] Sticky channel + Fade Off behave
- [ ] Short names / whisper ding / mention highlight
- [ ] No timestamps module shipped
- [ ] No Lua errors in chat

## Report back (template for Lead chat)

```
UAT G — Chat Kit: PASS | FAIL
Notes:
- 
Local fixes pushed? yes/no — PR #22
Ready for Lead to merge? yes/no
```
