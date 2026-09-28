---
name: deploy
description: Ship Skylight to production (www.skylight.sh) and verify it. Use when the user asks to deploy, ship, push, release or publish, or to check what production is running.
---

# Deploy

Pushing to `main` **is** the production deploy: GitHub `adamtowerz/skylight` is connected to the
Vercel project `adamtowerzs-projects/skylight`, which builds every push to `main`. Push only
when the user has asked for it; experiments stay local.

1. Checks: `npx tsc --noEmit`, `npx next build` (route `/` must stay `○` static), and the
   render-review matrix for anything visual.
2. Commit, then catch up and push. Conductor workspaces cannot check out `main`, so push the
   branch head to it:
   ```sh
   git fetch origin && git rebase origin/main      # other sessions push to main too
   git push origin HEAD:main
   ```
3. Wait for Vercel's commit status (`pending` → `success`, usually a minute or two):
   ```sh
   gh api repos/adamtowerz/skylight/commits/$(git rev-parse HEAD)/status --jq .state
   ```
   On `failure`, the `target_url` in `--jq '.statuses[]'` links the build log.
4. Verify production itself:
   ```sh
   curl -sI https://www.skylight.sh/ | head -1            # HTTP/2 200
   node scripts/screenshot.mjs --url 'https://www.skylight.sh/?hour=18.8&speed=0' \
     --out .context/prod.png --wait 6000                   # then look at it
   ```
   The CDN serves the new HTML as soon as the deployment is promoted (`s-maxage` is purged per
   deployment); if the screenshot shows the old look, check step 3 again before suspecting cache.
