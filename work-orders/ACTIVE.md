# ACTIVE work order

**Updated:** 2026-10-02 (CT)  
**Status:** **Launch cut `v1.4.0` shipped** (A + C + D + E + launch menu). Next UAT: Package B (not in launch tag).

## Do this next

| Field | Value |
|-------|-------|
| **WO** | [WO-B-quiet-errors](uat/WO-B-quiet-errors.md) |
| **Package** | B — Quiet Errors |
| **PR** | https://github.com/crumpshot-forever/ForeverForge/pull/14 |
| **Branch** | `feat/package-b-quiet-errors` |
| **Issue** | #4 (`lane:uat`) |
| **Note** | Rebase onto post-`v1.4.0` `main` before UAT / merge |

### Grok Build one-liner (paste)

```
Pull ForeverForge, open work-orders/ACTIVE.md, checkout the PR branch listed there (rebase onto origin/main first if Lead says so), install that build into my WoW Forever addons folder, and help me UAT Package B (Quiet Errors). Do not merge or tag. After we finish, summarize pass/fail + any fixes for me to paste to FF Founding Lead.
```

## Done / shipped in `v1.4.0`

- A Vendor Stop — merged PR #13 · issue #2 → `lane:released`
- C Mail Kit — merged PR #15 · Mail Expire Alert only (Rapid Mail dropped) · issue #3 → `lane:released`
- D NPC Flow — merged PR #16 · issue #5 → `lane:released`
- E Quick Accept — merged PR #17 · issue #6 → `lane:released`
- Launch menu pass — merged PR #29 · tag **`v1.4.0`**

## Still open (not in `v1.4.0`)

1. B Quiet Errors — [WO-B](uat/WO-B-quiet-errors.md) · PR #14 · **ACTIVE**
2. F Durability — [WO-F](uat/WO-F-durability.md) · PR #18
3. G Chat Kit — [WO-G](uat/WO-G-chat-kit.md) · PR #22

## Board

- https://crumpshot-forever.github.io/ForeverForge/board.html  
- Mirror: [SPRINT.md](SPRINT.md)
