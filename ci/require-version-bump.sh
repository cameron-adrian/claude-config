#!/usr/bin/env bash
# Refuse a change to the plugin that forgets to move its version.
#
# The failure this exists for is the most consequential silent one this repo
# has. Installs only pick up new hook code when `version` in plugin.json moves,
# so a change to plugins/house/ that forgets the bump ships nothing: every
# machine and every cloud session keeps running the old scripts, while the PR
# is green and the commit sits on main looking done. Nothing about that is
# visible until someone notices months later that a fix never took effect.
#
# Usage:  bash ci/require-version-bump.sh <base-ref>
#
# Exit 0 = fine (either no plugin change, or the version moved).
# Exit 1 = plugin changed and the version did not.
#
# Unlike the session hooks, this does NOT fail open. A hook that wedges a
# session is worse than the bug it watches for; a CI check that cannot tell
# whether it is safe has no such excuse and should say so loudly.

set -eu

BASE="${1:-}"
[ -n "$BASE" ] || { echo "usage: $0 <base-ref>" >&2; exit 2; }

MANIFEST="plugins/house/.claude-plugin/plugin.json"
WATCHED="plugins/house/"

# Same interpreter resolution the test suite uses: Git Bash on Windows has `py`
# and `python` but no `python3`, CI runners have `python3`. Hard-coding either
# works on one machine and errors on the other.
PY_BIN=""
for c in python3 python py; do
  command -v "$c" >/dev/null 2>&1 && { PY_BIN="$c"; break; }
done
[ -n "$PY_BIN" ] || { echo "no python interpreter found" >&2; exit 2; }

git rev-parse --verify --quiet "$BASE" >/dev/null || {
  echo "base ref '$BASE' is not reachable; cannot tell whether the plugin changed" >&2
  exit 2
}

# Three dots: compare against the merge base, so unrelated commits that landed
# on the target branch in the meantime do not read as plugin edits here.
if git diff --quiet "$BASE"...HEAD -- "$WATCHED"; then
  echo "No changes under $WATCHED -- version bump not required."
  exit 0
fi

echo "Changed under $WATCHED:"
git diff --name-only "$BASE"...HEAD -- "$WATCHED" | sed 's/^/  /'

read_version() {  # plugin.json on stdin -> version on stdout
  "$PY_BIN" -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}

[ -f "$MANIFEST" ] || { echo "$MANIFEST is missing from this commit" >&2; exit 1; }
new=$(read_version <"$MANIFEST")

# A manifest that does not exist on the base is a first release, not a
# forgotten bump.
if ! git cat-file -e "$BASE:$MANIFEST" 2>/dev/null; then
  echo "No $MANIFEST on $BASE -- treating $new as the first release."
  exit 0
fi

old=$(git show "$BASE:$MANIFEST" | read_version)

if [ "$old" = "$new" ]; then
  cat >&2 <<EOF

$WATCHED changed but version is still $old.

Installs only pick up new hook code when that field moves, so merging this
as-is ships the change to nobody -- every machine keeps running the old
scripts. Bump 'version' in $MANIFEST.
EOF
  exit 1
fi

echo "Version moved $old -> $new."
exit 0
