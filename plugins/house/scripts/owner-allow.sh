#!/bin/sh
# PreToolUse on Bash. Auto-approves the everyday git write flow, but ONLY when
# the repo's `origin` belongs to a trusted GitHub account. Anywhere else it
# stays silent and the normal permission prompt happens.
#
# It never denies. git-gate.sh runs on the same event and still refuses the
# handful of git operations that are hard to undo -- a force-push or a direct
# push to the default branch, merging a draft or red PR. A deny from it
# outranks the allow from here, so widening this list cannot punch a hole in
# those.
#
# Trusted owners default to the owner of this plugin's marketplace repo
# (cameron-adrian). Set HOUSE_TRUSTED_OWNERS to a space- or comma-separated
# list to replace that -- e.g. to add GitHub orgs you administer.
#
# FAIL OPEN, like every house hook: no interpreter, no origin, a command shape
# the vetting does not recognise -- all of those exit without a decision and
# leave the prompt exactly where it was.
#
# shellcheck disable=SC2016
# The single-quoted string passed to `house_py -c` is python source, not shell.
# Nothing in it is meant to expand.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

DEFAULT_OWNERS="cameron-adrian"

input=$(cat)
house_enter_payload_cwd "$input"
cmd=$(printf '%s' "$input" | house_json_field tool_input.command)

[ -n "$cmd" ] || exit 0

# Cheap bail before shelling out to git at all.
case "$cmd" in
  *git*|*gh*) ;;
  *) exit 0 ;;
esac

house_in_repo || exit 0

url=$(git remote get-url origin 2>/dev/null) || exit 0
[ -n "$url" ] || exit 0

owners="${HOUSE_TRUSTED_OWNERS:-$DEFAULT_OWNERS}"

# One python pass does both halves: work out who owns `origin`, and decide
# whether every segment of the command is something we are willing to wave
# through. Prints ALLOW only when both hold.
verdict=$(printf '%s' "$cmd" | house_py -c '
import sys, re, shlex

cmd = sys.stdin.read()
url = sys.argv[1].strip()
owners = {o.lower() for o in re.split(r"[,\s]+", sys.argv[2]) if o.strip()}

if not cmd or "\x00" in cmd or len(cmd) > 8000:
    sys.exit(0)

# ---- owner of origin ---------------------------------------------------------
u = re.sub(r"\.git/?$", "", url)
m = re.match(r"^[^/@]+@([^:/]+):(.+)$", u)                       # git@github.com:owner/repo
if not m:
    m = re.match(r"^[a-zA-Z][\w+.-]*://(?:[^@/]+@)?([^/]+)/(.+)$", u)  # https:// , ssh://
if not m:
    sys.exit(0)
host, path = m.group(1).lower(), m.group(2)
if host != "github.com" and not host.endswith(".github.com"):
    sys.exit(0)
parts = [p for p in path.split("/") if p]
if not parts or parts[0].lower() not in owners:
    sys.exit(0)

# ---- is every segment of the command something we will approve? -------------
GIT_OK = {
    "add", "commit", "push", "pull", "fetch", "checkout", "switch", "merge",
    "rebase", "reset", "rm", "restore", "branch", "tag", "cherry-pick",
    "worktree",
}
GH_PR_OK = {"create", "merge", "ready", "edit"}

# shlex with punctuation_chars is the documented recipe for shell-like
# tokenising: it keeps "..." / \x27...\x27 / "$(...)" as single tokens and
# breaks && || ; | ( ) < > out on their own. A commit message that carries a
# literal && is therefore safe as long as it is quoted (the common
# git commit -m "$(cat <<EOF ...)" form tokenises whole); an unquoted heredoc
# trips the < guard below and falls through to a prompt, which is the safe
# direction.
lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
lex.whitespace_split = True
lex.commenters = ""
try:
    tokens = list(lex)
except ValueError:
    sys.exit(0)   # unbalanced quotes and the like -> let the prompt happen

BREAK = {"&&", "||", ";", "|", "&"}
saw_target = False
segment = []

def vet(seg):
    toks = list(seg)
    while toks and (re.match(r"^\w+=", toks[0]) or toks[0] == "cd"):
        if toks[0] == "cd":
            return None            # a bare directory change: nothing to vet
        toks = toks[1:]
    if not toks:
        return None
    if toks[0] == "git" and len(toks) >= 2 and toks[1] in GIT_OK:
        return True
    if (toks[0] == "gh" and len(toks) >= 3
            and toks[1] == "pr" and toks[2] in GH_PR_OK):
        return True
    return False                   # an unrecognised segment

for t in tokens:
    if t in ("<", ">", ">>", "(", ")"):
        sys.exit(0)                 # redirection / subshell: out of scope, prompt
    if t in BREAK:
        r = vet(segment)
        if r is False:
            sys.exit(0)
        if r is True:
            saw_target = True
        segment = []
        continue
    segment.append(t)

r = vet(segment)
if r is False:
    sys.exit(0)
if r is True:
    saw_target = True

if saw_target:
    sys.stdout.write("ALLOW")
' "$url" "$owners" 2>/dev/null)

[ "$verdict" = "ALLOW" ] || exit 0

house_allow "Trusted-owner repo (origin is a github.com repo owned by an account in HOUSE_TRUSTED_OWNERS): the everyday git write flow is auto-approved by the house plugin. git-gate.sh still guards force / direct pushes to the default branch and draft or red-CI merges."
