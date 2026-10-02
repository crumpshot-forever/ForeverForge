# CurseForge release (BigWigs packager CI)

Forever Forge publishes to [CurseForge](https://www.curseforge.com/wow/addons/forever-forge) (project id **1714676**) via the [BigWigs Mods packager](https://github.com/BigWigsMods/packager) GitHub Action. Pushing an annotated tag `vX.Y.Z` runs `.github/workflows/release.yml`, builds the zip, and uploads it.

Do **not** put API tokens in the repo, workflow files, or docs. Secrets live only in GitHub Actions secrets (and optionally a local `.env` you never commit).

## Why packager CI (not CF GitHub App alone)

CurseForge’s GitHub App / tag auto-import can miss tags or stall with no actionable log in this repo. Packager CI is durable: every matching tag runs an Actions job you can inspect, uploads with the CurseForge API, and also attaches a GitHub Release asset. Prefer that path for post-UAT releases.

## One-time setup (Jase / Lead)

1. **Create a CurseForge API token**  
   Authors: [CurseForge API tokens](https://authors.curseforge.com/#/settings/api-tokens) (WoW CF tokens also linked from author tooling). Copy the token once; store it in a password manager.

2. **Add the GitHub Actions secret** (exact name — must match the workflow):  
   Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**  
   - Name: `CF_API_KEY`  
   - Value: the CurseForge token  

3. **Optional — Wago**  
   If you want the same tag uploaded to Wago Addons: create a token at [Wago API keys](https://addons.wago.io/account/apikeys), add secret `WAGO_API_TOKEN`, and add `## X-Wago-ID: <id>` to `ForeverForge.toc` (id from the Wago developer dashboard). Until then, the workflow still runs; Wago upload is simply skipped when the secret is empty.

4. **GitHub Release permission**  
   The workflow sets `permissions: contents: write` so the default `GITHUB_TOKEN` can create the GitHub Release. If you see `Resource not accessible by integration`, check repo **Settings → Actions → General → Workflow permissions** includes read and write.

5. **Do not** commit tokens, paste them into issues/PR bodies, or put them in `.env` that gets pushed.

## Release flow

1. Merge the release-ready work to `main` (e.g. after UAT packages A–G).  
2. Ensure `ForeverForge.toc` still has `## X-Curse-Project-ID: 1714676` and `## Version: @project-version@` (packager replaces the keyword from the tag).  
3. Create an **annotated** tag and push it:

   ```bash
   git checkout main
   git pull
   git tag -a v1.1.0 -m "v1.1.0"
   git push origin v1.1.0
   ```

4. Actions → **Package and release** runs on that tag. On success: zip on CurseForge, GitHub Release for the tag, optional Wago if configured.  
5. Manual dry-run: **Actions → Package and release → Run workflow** (`workflow_dispatch`). Untagged / dispatch builds are treated as **alpha** by the packager; production CF “Release” channel needs a real `v*` tag.

## Current CurseForge state

- CF still has the **manual** 1.0.0 upload (Sep 27, 2026). Tags `v1.0.1`–`v1.0.8` existed on GitHub but never landed on CF (no packager workflow on `main`; CF App did not ingest those tags).  
- After `CF_API_KEY` is set and this workflow is on `main`, the **next** `v*` tag publishes automatically. You do not need to re-upload old tags unless you choose to.

## Metadata checklist

| Item | Location |
|------|----------|
| Package name | `.pkgmeta` → `package-as: ForeverForge` |
| CF project id | `ForeverForge.toc` → `X-Curse-Project-ID: 1714676` |
| Ignores | `.pkgmeta` ignores `docs`, `.github`, `Screenshots`, `CURSEFORGE.md` |
| Secret name | `CF_API_KEY` (optional `WAGO_API_TOKEN`) |

## References

- [BigWigs packager README](https://github.com/BigWigsMods/packager)  
- [GitHub Actions workflow wiki](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow)  
- Forever Forge on CurseForge: https://www.curseforge.com/wow/addons/forever-forge  
