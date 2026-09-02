#!/bin/sh
# SessionStart. Puts the repo's actual state in front of the session before it
# can claim anything about it.
#
# The failure this answers: asked what had changed in the last 48 hours, a
# session ran `git log --all --since=...` in a fresh clone that held only main,
# got nothing, and reported that nothing had been pushed. The remote had four
# branches and three PRs, one with ten commits from that same day. `--all` means
# "all refs I have", not "all refs there are", and it gave a confident empty
# answer instead of an incomplete one.
#
# So the ref comparison here is against `git ls-remote` -- the remote's own
# answer -- rather than against anything local. A fetch runs too, but nothing
# below depends on it having finished.
#
# Plain text on stdout: SessionStart is one of the events where stdout becomes
# context the session can act on.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

house_in_repo || exit 0

# Warm the local refs for whatever comes next. Backgrounded and never waited on,
# so a slow remote costs the session nothing at startup.
(git fetch --all --prune --tags --quiet >/dev/null 2>&1 &) 2>/dev/null

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
default=$(house_default_branch)

printf '## Repo state at session start\n\n'
printf -- '- Branch: `%s`' "$branch"
[ -n "$default" ] && [ "$branch" = "$default" ] && printf ' (the default branch)'
printf '\n'

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
if [ -n "$upstream" ]; then
  counts=$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
  behind=$(printf '%s' "$counts" | awk '{print $1}')
  ahead=$(printf '%s' "$counts" | awk '{print $2}')
  [ "${ahead:-0}" != "0" ] && printf -- '- **%s local commit(s) not pushed.**\n' "$ahead"
  [ "${behind:-0}" != "0" ] && printf -- '- **%s commit(s) on %s you do not have.**\n' "$behind" "$upstream"
else
  printf -- '- No upstream set for this branch.\n'
fi

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "${dirty:-0}" != "0" ] && printf -- '- %s file(s) with uncommitted changes.\n' "$dirty"

# The ref-truth check. Anything the remote has that this clone does not is
# exactly what a --all query would silently miss.
remote_heads=$(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||')
if [ -n "$remote_heads" ]; then
  missing=""
  for h in $remote_heads; do
    git show-ref --verify --quiet "refs/remotes/origin/$h" || missing="$missing $h"
  done
  if [ -n "$missing" ]; then
    printf -- '- **This clone is missing remote branches:**%s\n' "$missing"
    printf -- '  `git log --all` does NOT cover these. Fetch before answering any\n'
    printf -- '  question about what has changed or shipped recently.\n'
  fi
fi

if command -v gh >/dev/null 2>&1; then
  prs=$(gh pr list --state open --limit 20 \
        --json number,title,isDraft,headRefName 2>/dev/null | house_py -c '
import sys, json
try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rows:
    print("  - #%s %s [%s]%s" % (
        r.get("number"), r.get("title", ""), r.get("headRefName", ""),
        "  DRAFT -- do not merge" if r.get("isDraft") else ""))
' 2>/dev/null)
  if [ -n "$prs" ]; then
    printf -- '- Open PRs:\n%s\n' "$prs"
  fi
fi

blocked_by=$(house_git_blocked)
if [ -n "$blocked_by" ]; then
  printf -- '- **This session cannot commit or push.** A deny rule in `%s`\n' "$blocked_by"
  printf -- '  blocks it. Deny rules are never prompted for and cannot be approved,\n'
  printf -- '  so do not offer to retry with permission. If work needs landing, say so\n'
  printf -- '  now and hand over a patch.\n'
fi

# How this repo is tested, so it does not have to be rediscovered.
tests=""
[ -f package.json ] && grep -q '"test"' package.json 2>/dev/null && tests="npm test"
[ -f bin/selftest.py ] && tests="py bin/selftest.py"
[ -f pytest.ini ] || [ -f pyproject.toml ] && [ -d tests ] && tests="${tests:-pytest}"
[ -f Cargo.toml ] && tests="cargo test"
[ -f go.mod ] && tests="go test ./..."
if [ -n "$tests" ]; then
  printf -- '- Tests: `%s`\n' "$tests"
elif house_has_ci; then
  printf -- '- CI exists but no local test command was detected.\n'
else
  printf -- '- **No tests and no CI in this repo.** Per house rules that is its own\n'
  printf -- '  PR -- see `/house:repo-doctor`.\n'
fi

exit 0
