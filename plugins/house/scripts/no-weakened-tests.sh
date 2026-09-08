#!/bin/sh
# PostToolUse on Write|Edit|MultiEdit. Reports a test or CI check that was just
# made weaker.
#
# Every other gate here protects the code. This one protects the signal. The
# house rule is that a green check is the substitute for reading the diff, which
# makes a suite that has been quietly skipped into worse than no suite at all:
# it does not merely fail to catch things, it actively reports that there was
# nothing to catch.
#
# So: a newly-added skip, an `.only` that silently drops every other test in the
# file, a `continue-on-error: true` that turns a red job green. Not the presence
# of those things -- their *arrival*. The diff against HEAD is what decides,
# because that is also what will land.
#
# Exit 2 on PostToolUse shows stderr to the session. Nothing is blocked and
# nobody is prompted; the write already happened. The session either justifies
# it or undoes it.
#
# Two dampers, both learned from the Stop hook that fired every turn until it
# got switched off:
#   - once per file per session, tracked by a marker, because the diff keeps
#     reporting the same line until it is committed
#   - `house-skip-ok` anywhere on the line stands the check down, so a
#     deliberate skip costs one comment rather than an argument every session
#
# shellcheck disable=SC2016
# The single-quoted blocks passed to `house_py -c` are python source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
house_enter_payload_cwd "$input"
f=$(printf '%s' "$input" | house_json_field tool_input.file_path)

[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

# Only files where a weakened check actually costs something: tests, and the
# workflows that run them. Everything else is none of this hook's business.
scope="test"
case "$f" in
  */.github/workflows/*|*\\.github\\workflows\\*) scope="workflow" ;;
  *test*|*Test*|*spec*|*Spec*) ;;
  *) exit 0 ;;
esac

house_in_repo || exit 0

# Added lines only. `git diff` against HEAD for a tracked file; the whole file
# for one git has never seen, since all of it is new.
if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
  added=$(git diff -U0 -- "$f" 2>/dev/null | grep '^+' | grep -v '^+++')
else
  added=$(sed 's/^/+/' "$f" 2>/dev/null)
fi

[ -n "$added" ] || exit 0

found=$(printf '%s' "$added" | house_py -c '
import re, sys

text = sys.stdin.read()
is_workflow = sys.argv[1] == "workflow"

# (regex, what it does to the signal, workflow-only?)
#
# The last three are scoped to CI workflow files on purpose. `|| true` at the
# end of a line is a red flag on a CI step and completely ordinary in a test
# fixture cleanup (`rm -rf "$TMP" || true`), and a gate that shouts at correct
# cleanup code is one that gets switched off before it ever catches the real
# thing.
PATTERNS = [
    (r"\b(?:describe|it|test|context)\.skip\s*\(",      "skips a test", False),
    (r"\b(?:describe|it|test|context)\.only\s*\(",      "runs ONLY this test and silently drops the rest of the file", False),
    (r"\b(?:fdescribe|fit)\s*\(",                       "runs ONLY this test and silently drops the rest of the file", False),
    (r"\b(?:xdescribe|xit|xtest)\s*\(",                 "skips a test", False),
    (r"@(?:pytest\.mark\.)?skip(?:if)?\b",              "skips a test", False),
    (r"@(?:pytest\.mark\.)?xfail\b",                    "expects a failure instead of asserting", False),
    (r"\bpytest\.skip\s*\(",                            "skips a test", False),
    (r"@unittest\.(?:skip|expectedFailure)",            "skips a test", False),
    (r"\bt\.Skip(?:Now|f)?\s*\(",                       "skips a test", False),
    (r"--passWithNoTests\b",                            "passes when no tests were found", False),
    (r"\bcontinue-on-error\s*:\s*true",                 "makes a failing CI job report green", True),
    (r"\bif\s*:\s*false\b",                             "stops a CI job from running at all", True),
    (r"\|\|\s*true\s*$",                                "throws away the exit code of a CI step", True),
]
PATTERNS = [p for p in PATTERNS if is_workflow or not p[2]]

hits = []
for raw in text.splitlines():
    if not raw.startswith("+"):
        continue
    line = raw[1:]
    # The escape hatch, per line: a deliberate skip carries its reason.
    if "house-skip-ok" in line:
        continue
    for pat, why, _ in PATTERNS:
        if re.search(pat, line):
            hits.append("  %s\n      -> %s" % (line.strip()[:120], why))
            break

sys.stdout.write("\n".join(hits[:10]))
' "$scope" 2>/dev/null) || exit 0

[ -n "$found" ] || exit 0

# One report per file per session. The diff keeps showing the same added line
# until it is committed, and a hook that repeats itself gets turned off.
sid=$(printf '%s' "$input" | house_json_field session_id)
[ -n "$sid" ] || sid="nosession"
key=$(printf '%s' "$sid$f" | house_py -c '
import hashlib, sys
sys.stdout.write(hashlib.sha1(sys.stdin.read().encode("utf-8")).hexdigest()[:16])
' 2>/dev/null)
if [ -n "$key" ]; then
  state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
  mkdir -p "$state_dir" 2>/dev/null
  marker="$state_dir/house-weak-$key"
  [ -f "$marker" ] && exit 0
  : > "$marker" 2>/dev/null
fi

{
  printf 'This write weakens a check rather than satisfying it:\n\n'
  printf '%s\n\n' "$found"
  printf 'In %s.\n\n' "$f"
  printf 'House rule: never get to green by weakening the check. A suite that\n'
  printf 'has been skipped does not just fail to catch things -- it reports that\n'
  printf 'there was nothing to catch, which is the one signal being merged on.\n\n'
  printf 'Fix the underlying failure instead. If the skip is genuinely correct --\n'
  printf 'an unsupported platform, a test for something deliberately unfinished --\n'
  printf 'say so out loud and put `house-skip-ok` on the line with the reason.\n'
} >&2

exit 2
