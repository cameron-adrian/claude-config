# shellcheck shell=sh
# Shared helpers for the house hooks. Sourced, never executed.
#
# The one rule every caller inherits: FAIL OPEN. A gate that cannot make up its
# mind must get out of the way. No python on PATH, no network, no gh, a repo
# shape nobody anticipated -- all of those exit 0 and let the call through. A
# gate that wedges a session is worse than the bug it was watching for, because
# the bug is occasional and the wedge is every single time.

# Run whichever python exists. Windows Git Bash has `py` and often `python`;
# Ubuntu cloud images have `python3`. Returns 127 if none of them do, which
# every caller treats as "skip this check".
house_py() {
  for _c in python3 python py; do
    if command -v "$_c" >/dev/null 2>&1; then
      "$_c" "$@"
      return $?
    fi
  done
  return 127
}

# Pull one dotted field out of the hook's JSON payload on stdin.
#
# Done in python rather than with grep, because on Windows every path in that
# payload arrives with escaped backslashes ("C:\\Users\\...") and a grep-based
# extractor hands back a path that does not exist. Empty output means absent,
# unreadable, or no interpreter -- callers cannot tell those apart and do not
# need to, since all three mean the same thing: skip.
house_json_field() {
  house_py -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].split("."):
    if isinstance(d, dict):
        d = d.get(k)
    else:
        d = None
    if d is None:
        break
if d is not None:
    sys.stdout.write(str(d))
' "$1" 2>/dev/null
}

# True when the working directory is inside a git repo.
house_in_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

# Enter the directory the hook's own JSON payload names as `cwd`, instead of
# trusting the shell's ambient working directory. $1 is the raw payload.
#
# This exists because two Bash tool calls that each start with `cd <repo>` can
# share one persistent shell. Running a job-search merge and a claude-config
# merge in the same batch let this hook fire for the claude-config command
# while the shared shell's directory was still mid-transition from the
# concurrent job-search one -- git-gate.sh ran `gh pr view` with no `-R`, it
# resolved against job-search's repo by ambient accident, found ITS draft PR
# with the same number, and refused a perfectly mergeable claude-config PR
# because of it. Reading the hook's own payload instead of the shell's shared
# state removes the race outright.
#
# Silent no-op when the field is missing or unreadable: the caller falls back
# to whatever the ambient cwd already is, exactly the old behavior.
house_enter_payload_cwd() {
  _dir=$(printf '%s' "$1" | house_json_field cwd)
  if [ -n "$_dir" ] && [ -d "$_dir" ]; then
    cd "$_dir" 2>/dev/null || true
  fi
  return 0
}

# The repo's default branch, as the remote reports it. Falls back through the
# usual suspects, then gives up with empty output -- callers gate on that rather
# than guessing "main" and acting on a wrong answer.
house_default_branch() {
  _d=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$_d" ]; then
    printf '%s' "${_d#origin/}"
    return 0
  fi
  for _b in main master; do
    if git show-ref --verify --quiet "refs/remotes/origin/$_b"; then
      printf '%s' "$_b"
      return 0
    fi
  done
  printf ''
}

# True when the repo runs CI. The push gate only applies where a green check
# actually means something; in a repo with no workflows, blocking a push to the
# default branch would be ceremony with nothing behind it.
house_has_ci() {
  [ -d .github/workflows ] || return 1
  for _f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$_f" ] && return 0
  done
  return 1
}

# True when this session is forbidden from committing or pushing by a deny rule
# somewhere in the settings stack.
#
# This exists because of a session that spent its whole length being told by a
# Stop hook to commit and push while the project settings denied both. The hook
# had no way to know the thing it demanded was impossible, so it repeated at
# every turn boundary, unsatisfiable by construction. Anything that is about to
# demand a commit asks this first.
house_git_blocked() {
  for _s in .claude/settings.json .claude/settings.local.json \
            "$HOME/.claude/settings.json"; do
    [ -f "$_s" ] || continue
    if grep -Eq '"Bash\(git (commit|push)[^"]*\)"' "$_s" 2>/dev/null; then
      # An allow entry with the same shape does not rescue it: deny wins
      # everywhere, at every layer, and is never prompted for.
      if house_py -c '
import sys, json
try:
    s = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
d = (s.get("permissions") or {}).get("deny") or []
import re
sys.exit(0 if any(re.match(r"Bash\(git (commit|push)", str(r)) for r in d) else 1)
' "$_s" 2>/dev/null; then
        printf '%s' "$_s"
        return 0
      fi
    fi
  done
  return 1
}

# Emit a PreToolUse denial. The reason is written to be acted on by the session
# rather than read by a person: it says what is wrong and what to do instead, so
# the session fixes it and retries without anyone being asked anything.
house_deny() {
  house_py -c '
import sys, json
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
' "$1" 2>/dev/null || {
    # No interpreter to build the JSON with. Fail open rather than blocking
    # with a message nothing can parse.
    exit 0
  }
  exit 0
}
