# Forever Forge work-orders (git as the bus)

**Rule:** if it is not here (or on a linked Issue/PR), it is not an assigned Build/UAT job.

| Surface | Role |
|---------|------|
| **FF Founding Lead chat** | HQ — greenlights, merge, release tags, bugs brought back from play |
| **This folder + sprint board** | Assignment bus Grok Build can `git pull` |
| **Grok Build (local)** | Workshop — checkout PR, install into WoW, UAT/troubleshoot, push fixes as PRs |

## How Jase uses this with Grok Build

1. `git pull` on `ForeverForge` (or open the PR branch named in `ACTIVE.md`).
2. Tell Build: *“Do UAT for the package in `work-orders/ACTIVE.md`”* or *“Bring over Package A from the sprint board.”*
3. Build reads `ACTIVE.md` → `work-orders/uat/WO-*.md` → checks out the PR branch → installs → you test in-game.
4. Pass/fail and any local fix notes go **back to FF Founding Lead chat** (Build does not merge, tag, or message the team).

## Canonical pointers

- Live board: https://crumpshot-forever.github.io/ForeverForge/board.html
- GitHub Issues (`lane:uat`): https://github.com/crumpshot-forever/ForeverForge/issues?q=is%3Aissue+label%3Alane%3Auat
- Build operating manual: [`docs/grok-build.md`](../docs/grok-build.md)
- Package definitions: [`SPRINT.md`](SPRINT.md) (Build-facing mirror of delivery packages)

Lead (or Eng under Lead) updates `ACTIVE.md` when the next UAT package is handed off.
