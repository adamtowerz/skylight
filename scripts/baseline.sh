#!/usr/bin/env bash
# Builds a git ref in a temporary worktree and serves it, so a "before" can run beside the
# working tree's "after":
#
#   scripts/baseline.sh [ref=HEAD] [port=3418]      # builds, then serves in the foreground
#   git worktree remove --force /tmp/skylight-<ref>  # when done
#
# The worktree gets a copy-on-write clone of node_modules rather than a symlink, because
# Turbopack refuses a node_modules that resolves outside the project root.
set -euo pipefail

ref="${1:-HEAD}"
port="${2:-3418}"
root="$(git rev-parse --show-toplevel)"
dir="/tmp/skylight-$(printf %s "$ref" | tr -c 'A-Za-z0-9._-' '-')"
sha="$(git rev-parse --verify "$ref^{commit}")"

if [ -d "$dir" ]; then
  git -C "$dir" checkout --quiet --detach "$sha"
else
  git worktree add --quiet --detach "$dir" "$sha"
fi
[ -d "$dir/node_modules" ] || cp -Rc "$root/node_modules" "$dir/node_modules"

echo "Building $ref ($(git rev-parse --short "$sha")) in $dir"
cd "$dir"
npx next build >/dev/null
echo "Serving $ref on http://localhost:$port"
exec npx next start -p "$port"
