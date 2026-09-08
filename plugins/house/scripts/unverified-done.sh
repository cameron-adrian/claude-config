#!/bin/sh
# Stop. One reminder, per session, that code changed and nothing was ever run.
#
# The most common failure in this whole list, and the least visible: a session
# edits source, reports the work done, and never once executes a test, a build,
# or so much as a parse. It reads as finished because nothing contradicted it.
# The house rule is explicit that a green check is the substitute for reading
# the diff, which makes "I did not run anything" the one thing that has to be
# said out loud rather than left for the next session to discover.
#
# The evidence is the transcript, not the repo: what matters is whether a
# verification command actually ran, and `git status` cannot answer that. One
# python pass collects every tool call the session made -- which files it wrote,
# which Bash commands it ran -- and the decision falls out of those two lists.
#
# FAIL OPEN, and specifically in the direction that matters here. If the
# transcript is missing, unparseable, or yields no tool calls at all, this hook
# says nothing. The failure mode of a transcript format change must be silence,
# not a nag at the end of every single session; the second one is how a hook
# gets switched off, taking the real catch with it.
#
# shellcheck disable=SC2016
# The single-quoted block passed to `house_py -c` is python source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)

transcript=$(printf '%s' "$input" | house_json_field transcript_path)
[ -n "$transcript" ] || exit 0
[ -f "$transcript" ] || exit 0

# Once per session. Same marker pattern as unpushed.sh, for the same reason:
# being wrong should cost one turn, not the rest of the session.
sid=$(printf '%s' "$input" | house_json_field session_id)
[ -n "$sid" ] || sid="nosession"
state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
mkdir -p "$state_dir" 2>/dev/null
marker="$state_dir/house-unverified-$sid"
[ -f "$marker" ] && exit 0

report=$(house_py -c '
import json, os, re, sys

path = sys.argv[1]

CODE = (
    "js mjs cjs jsx ts tsx py sh bash zsh rb go rs java kt swift "
    "c h cc cpp hpp cs php lua sql vue svelte astro tf ps1"
).split()

# Generous on purpose. Every entry here is something that could plausibly have
# told the session it was wrong, and a missed nag costs nothing while a wrong
# one costs the hook.
VERIFY = re.compile(r"""
    \b(?:
        pytest|unittest|tox|nox|
        jest|vitest|mocha|ava|karma|cypress|playwright|
        rspec|minitest|bats|
        phpunit|
        go\s+(?:test|build|vet)|
        cargo\s+(?:test|build|check|clippy)|
        dotnet\s+(?:test|build)|
        swift\s+(?:test|build)|
        deno\s+(?:test|check)|
        mvn|gradle|make|cmake|
        tsc|eslint|ruff|flake8|mypy|pyright|shellcheck|rubocop|
        npm\s+(?:test|run|ci)|yarn|pnpm\s+(?:test|run)|bun\s+(?:test|run)|
        gh\s+(?:pr\s+checks|run\s+(?:watch|view))
    )\b
    | node\s+--check
    | sh\s+-n\b
    | bash\s+[\w./-]*tests?[\w./-]*
    | \./(?:tests?|scripts?)/[\w.-]+
    | python3?\s+-m\s+(?:pytest|unittest)
""", re.X)

edited, commands, saw_tool = set(), [], False

def walk(node):
    global saw_tool
    if isinstance(node, dict):
        if node.get("type") == "tool_use" and isinstance(node.get("input"), dict):
            saw_tool = True
            name = str(node.get("name", ""))
            inp = node["input"]
            if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                p = inp.get("file_path") or inp.get("notebook_path")
                if p:
                    edited.add(str(p))
            elif name == "Bash":
                c = inp.get("command")
                if c:
                    commands.append(str(c))
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

try:
    # A long session produces a large transcript; line at a time, and a single
    # malformed line must not discard everything before it.
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                walk(json.loads(line))
            except Exception:
                continue
except Exception:
    sys.exit(0)

# No tool calls found at all means the transcript is not shaped the way this
# expects. That is a reason to stay quiet, not to guess.
if not saw_tool:
    sys.exit(0)

source = sorted(p for p in edited
                if os.path.splitext(p)[1][1:].lower() in CODE)
if not source:
    sys.exit(0)

if any(VERIFY.search(c) for c in commands):
    sys.exit(0)

shown = [os.path.basename(p) for p in source[:6]]
if len(source) > 6:
    shown.append("and %d more" % (len(source) - 6))
sys.stdout.write("%d source file(s) changed: %s" % (len(source), ", ".join(shown)))
' "$transcript" 2>/dev/null) || exit 0

[ -n "$report" ] || exit 0

: > "$marker" 2>/dev/null

{
  printf 'Nothing was ever run against this work:\n\n'
  printf '  - %s\n' "$report"
  printf '  - no test, build, lint or parse command in the whole session\n\n'
  printf 'House rule is that a green check is the substitute for reading the\n'
  printf 'diff, so code that has not been executed is not finished being\n'
  printf 'checked. Run this repo'"'"'s suite now if it has one.\n\n'
  printf 'If it has no suite, that is itself worth acting on -- the rule says a\n'
  printf 'repo without tests gets one set up as its own pull request. And if\n'
  printf 'this session genuinely could not run anything, say so plainly rather\n'
  printf 'than reporting the work as verified. This will not ask again.\n'
} >&2

exit 2
