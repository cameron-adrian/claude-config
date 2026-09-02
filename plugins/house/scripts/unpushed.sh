#!/bin/sh
# Stop. One reminder, per session, that work is sitting uncommitted.
#
# The version of this that prompted the rewrite fired at every single turn
# boundary for a whole session, demanding a commit while the project settings
# denied `Bash(git commit *)` and `Bash(git push *)`. Unsatisfiable by
# construction, and nothing in the loop noticed the contradiction.
#
# So two constraints, both load-bearing:
#   1. It asks whether committing is even permitted before demanding one.
#   2. It fires at most once per session, tracked by a marker file, so being
#      wrong costs one turn rather than the rest of the session.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
house_in_repo || exit 0

# If a rule forbids the thing this hook is about to ask for, say nothing at all.
house_git_blocked >/dev/null && exit 0

sid=$(printf '%s' "$input" | house_json_field session_id)
[ -n "$sid" ] || sid="nosession"

state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
mkdir -p "$state_dir" 2>/dev/null
marker="$state_dir/house-stop-$sid"
[ -f "$marker" ] && exit 0

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
ahead=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
fi

[ "${dirty:-0}" = "0" ] && [ "${ahead:-0}" = "0" ] && exit 0

: > "$marker" 2>/dev/null

{
  printf 'Work in this repo is not landed yet:\n'
  [ "${dirty:-0}" != "0" ] && printf -- '  - %s file(s) with uncommitted changes\n' "$dirty"
  [ "${ahead:-0}" != "0" ] && printf -- '  - %s commit(s) not pushed\n' "$ahead"
  printf '\nHouse rule is commit and push after every change, with the message\n'
  printf 'written from the actual diff. Check `git status` first for anything you\n'
  printf 'did not touch and commit that separately.\n\n'
  printf 'If some of this is deliberately being left -- generated state, a\n'
  printf 'half-finished experiment -- say which and why, and carry on. This will\n'
  printf 'not ask again in this session either way.\n'
} >&2

exit 2
