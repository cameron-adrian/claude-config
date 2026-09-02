#!/bin/sh
# PreToolUse on Bash. Gates three commands that are hard or impossible to undo.
#
# Every refusal names the fix, because the audience is the session, not a
# person: it reads the reason, does the thing, and retries. Nothing here ever
# surfaces as a prompt.
#
# Escape hatch: put `#gate-ok` anywhere in the command and every gate stands
# down. It is there so a deliberate exception costs one comment instead of a
# stuck session, and so the gates can be tightened without fear of wedging.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
cmd=$(printf '%s' "$input" | house_json_field tool_input.command)

[ -n "$cmd" ] || exit 0
case "$cmd" in *'#gate-ok'*) exit 0 ;; esac
case "$cmd" in *git*|*gh*) ;; *) exit 0 ;; esac

house_in_repo || exit 0
default=$(house_default_branch)

# ---------------------------------------------------------------- git push
case "$cmd" in
  *"git push"*)
    [ -n "$default" ] || exit 0

    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Which branch is this push aimed at? Parse it as git does --
    # `git push [flags] [remote] [refspec]` -- rather than looking for the
    # default branch's name anywhere in the line. Scanning for the name is what
    # an earlier version did, and it refused `git push -u origin my-feature`
    # while main happened to be checked out: the target was read as the current
    # branch because no word matched. A gate that fires on correct input is the
    # failure mode that gets gates deleted.
    target=""
    seen_push=0
    remote_seen=0
    for w in $cmd; do
      if [ "$seen_push" = 0 ]; then
        [ "$w" = "push" ] && seen_push=1
        continue
      fi
      case "$w" in
        '&&'|'||'|';'|'|') break ;;
        -*) continue ;;
      esac
      if [ "$remote_seen" = 0 ]; then
        remote_seen=1
        continue
      fi
      # A refspec may be src:dst; only the destination matters.
      target="${w##*:}"
      break
    done
    [ -n "$target" ] || target="$current"

    case "$cmd" in
      # --force-with-lease is covered by the --force pattern; listing it
      # separately would be dead.
      *" --force"*|*" -f "*)
        if [ "$target" = "$default" ]; then
          house_deny "Refusing a force-push to $default.

Rewriting history on the default branch discards commits for everyone and every
clone, including the ones a cloud session may have pushed since you last looked.

If you are certain, re-run with #gate-ok appended and say in your next message
what is being discarded and why."
        fi
        ;;
    esac

    if [ "$target" = "$default" ] && house_has_ci; then
      house_deny "Refusing a direct push to $default: this repo has CI, and a
direct push routes around it.

Branch and open a PR instead:

  git switch -c <branch>
  git push -u origin <branch>
  gh pr create --fill

CI is the only review this repo gets, so it has to be in the path. If this push
genuinely should skip it -- a docs typo, a state file -- append #gate-ok."
    fi
    ;;
esac

# ------------------------------------------------------------- gh pr merge
case "$cmd" in
  *"gh pr merge"*)
    command -v gh >/dev/null 2>&1 || exit 0

    # A PR number in the command wins; otherwise gh resolves the current branch.
    prnum=""
    for w in $cmd; do
      case "$w" in
        ''|*[!0-9]*) ;;
        *) prnum="$w"; break ;;
      esac
    done

    # An empty $prnum has to disappear from the argument list entirely rather
    # than be passed as "", which gh reads as a PR named "" and errors on. With
    # no number, gh resolves the PR for the current branch, which is what a bare
    # `gh pr merge` means.
    if [ -n "$prnum" ]; then
      info=$(gh pr view "$prnum" --json isDraft,mergeStateStatus,statusCheckRollup,title 2>/dev/null) || exit 0
    else
      info=$(gh pr view --json isDraft,mergeStateStatus,statusCheckRollup,title 2>/dev/null) || exit 0
    fi
    [ -n "$info" ] || exit 0

    verdict=$(printf '%s' "$info" | house_py -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if d.get("isDraft"):
    print("DRAFT")
    sys.exit(0)

rollup = d.get("statusCheckRollup") or []
pending, failing = [], []
for c in rollup:
    # Checks and legacy statuses report their result under different keys.
    state = c.get("conclusion") or c.get("state") or ""
    name = c.get("name") or c.get("context") or "check"
    if state in ("", "PENDING", "IN_PROGRESS", "QUEUED", "WAITING", "EXPECTED"):
        pending.append(name)
    elif state not in ("SUCCESS", "NEUTRAL", "SKIPPED"):
        failing.append("%s (%s)" % (name, state))

if failing:
    print("FAILING:" + ", ".join(failing))
elif pending:
    print("PENDING:" + ", ".join(pending))
else:
    print("STATE:" + str(d.get("mergeStateStatus") or ""))
' 2>/dev/null)

    case "$verdict" in
      DRAFT)
        house_deny "This PR is a draft, so it is not ready to merge.

Draft is the deliberate gate: it means the PR is waiting on a review, a live
test, or something outside git. Do not un-draft it in order to merge it. Leave
it and say what it is waiting on."
        ;;
      FAILING:*)
        house_deny "CI is not green on this PR: ${verdict#FAILING:}

Merging now lands a known-broken commit on the default branch. Fix the failure
and push; the checks re-run on their own."
        ;;
      PENDING:*)
        house_deny "CI has not finished on this PR: ${verdict#PENDING:}

Wait for it rather than merging on the assumption it passes:

  gh pr checks $prnum --watch

Then merge once it comes back green."
        ;;
      STATE:BEHIND)
        house_deny "The base branch has moved since this PR was created, so what
CI tested is not what would land.

This is the case where two branches each bump a version independently and only
collide after the merge. Update the branch first:

  gh pr update-branch $prnum

Then let CI re-run against the new base before merging."
        ;;
      STATE:DIRTY)
        house_deny "This PR has merge conflicts against its base and cannot be
merged as-is. Rebase or merge the base in, resolve the conflicts, and push.

Resolve them with the Edit tool rather than by splicing the conflict markers out
with a script -- that is how a closing brace got eaten last time."
        ;;
      STATE:BLOCKED)
        house_deny "GitHub reports this PR as blocked -- branch protection, a
required review, or a required check that has not reported.

Say what the requirement is rather than looking for a way around it."
        ;;
    esac
    ;;
esac

exit 0
