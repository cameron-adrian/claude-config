#!/bin/sh
# PreToolUse on Bash. Keeps a recursive sweep out of a file the repo has
# deliberately put behind a deny rule.
#
# A `deny` entry naming one specific file -- `Read(state/config.json)` -- is
# almost always there to keep a previously-leaked secret out of context, and
# nothing overrides it: not an allow entry, not an auto-accept mode. So a
# `grep -r` that wanders into it does not read it. It stops dead and demands a
# manual approval that can never be granted, which turns an unrelated
# repo-wide search into an interruption for no reason at all.
#
# The house rule already says to check the settings files and scope the sweep
# around those paths. Nothing ever remembers, because the cost of forgetting
# lands several seconds later and looks like an unrelated prompt. This reads
# the settings files itself and hands back the corrected command.
#
# Escape hatch: `#gate-ok`, same as every other Bash gate here.
#
# shellcheck disable=SC2016
# The single-quoted block passed to `house_py -c` is python source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
house_enter_payload_cwd "$input"
cmd=$(printf '%s' "$input" | house_json_field tool_input.command)

[ -n "$cmd" ] || exit 0
case "$cmd" in *'#gate-ok'*) exit 0 ;; esac

# Cheap bail: only the sweeping tools are of interest.
case "$cmd" in
  *grep*|*find*|*rg*|*ack*|' ag '*|*ls*) ;;
  *) exit 0 ;;
esac

# No settings files with deny rules means there is nothing to protect.
[ -f .claude/settings.json ] || [ -f .claude/settings.local.json ] || exit 0

verdict=$(printf '%s' "$cmd" | house_py -c '
import json, os, re, shlex, sys

cmd = sys.stdin.read()
if not cmd or len(cmd) > 8000:
    sys.exit(0)

# ------------------------------------------------- what is behind a deny rule
denied = []
for s in (".claude/settings.json", ".claude/settings.local.json"):
    try:
        with open(s, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        continue
    for rule in ((data.get("permissions") or {}).get("deny") or []):
        m = re.match(r"Read\((.+)\)$", str(rule).strip())
        if m:
            p = m.group(1).strip().strip("\"\x27")
            if p and p not in ("*", "**", "**/*"):
                denied.append(p)

if not denied:
    sys.exit(0)

# ------------------------------------------------------ is this a broad sweep
try:
    tokens = shlex.split(cmd, comments=False)
except Exception:
    # Unbalanced quotes, a heredoc, something this has no business guessing at.
    sys.exit(0)

tool = None
recursive = False
for i, t in enumerate(tokens):
    base = os.path.basename(t)
    if base in ("grep", "egrep", "fgrep", "ack"):
        tool = "grep"
        if any(re.match(r"-[a-zA-Z]*[rR]", x) or x == "--recursive"
               for x in tokens[i + 1:]):
            recursive = True
    elif base in ("rg", "ripgrep", "ag"):
        tool, recursive = "rg", True   # recursive by default
    elif base == "find":
        tool, recursive = "find", True
    elif base == "ls":
        if any(re.match(r"-[a-zA-Z]*R", x) for x in tokens[i + 1:]):
            tool, recursive = "ls", True

if not tool or not recursive:
    sys.exit(0)

# --------------------------------------------------- would it reach the file?
# Directory arguments that actually exist, which is the closest thing to a
# reliable read of where the sweep is pointed without reimplementing each
# tool"s argument grammar. No directory argument means it defaults to here.
roots = [t for t in tokens[1:] if not t.startswith("-") and os.path.isdir(t)]
if not roots:
    roots = ["."]

def in_scope(p):
    if any(ch in p for ch in "*?["):
        return True          # a glob could match anywhere below any root
    if not os.path.exists(p):
        return False         # nothing there to walk into
    try:
        target = os.path.realpath(p)
    except Exception:
        return True
    for r in roots:
        try:
            root = os.path.realpath(r)
        except Exception:
            continue
        if target == root or target.startswith(root + os.sep):
            return True
    return False

# Already handled: the command names the path or its basename somewhere, which
# for these tools means an --exclude, a --glob, or a -not -path.
def already_excluded(p):
    return p in cmd or os.path.basename(p) in cmd

at_risk = [p for p in denied if in_scope(p) and not already_excluded(p)]
if not at_risk:
    sys.exit(0)

# ------------------------------------------------------------- the correction
def fix(p):
    base = os.path.basename(p)
    is_dir = os.path.isdir(p)
    if tool == "grep":
        return "--exclude-dir=%s" % base if is_dir else "--exclude=%s" % base
    if tool == "rg":
        return "--glob \x27!%s\x27" % p
    if tool == "find":
        return "-not -path \x27*/%s*\x27" % base
    return "(no exclude flag for ls -R; narrow the path instead)"

lines = ["  - %s   ->  add  %s" % (p, fix(p)) for p in at_risk]
sys.stdout.write("\n".join(lines))
' 2>/dev/null) || exit 0

[ -n "$verdict" ] || exit 0

house_deny "This recursive sweep walks into a path the repo denies reading:

$verdict

A deny rule naming one specific file is there on purpose -- almost always to
keep a leaked secret out of context -- and nothing overrides it. The sweep will
not read the file; it will stop and ask for an approval that cannot be granted,
turning an unrelated search into an interruption.

Re-run it with the exclusion above. If the path genuinely needs to be in scope,
\`#gate-ok\` on the command runs it as written."
