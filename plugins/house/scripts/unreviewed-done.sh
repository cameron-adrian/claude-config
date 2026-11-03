#!/bin/sh
# Stop. One reminder, per session, that code changed and nobody else checked it.
#
# The house rule is that work is done only after someone who did not write it
# has reviewed it: the house `reviewer` agent in a fresh context, given the
# user's original request. Builders overrate their own work, and "obviously not
# what I meant" is the correction users make most often. This hook is the
# reminder for the session that skipped that step, or that kept editing after
# its last review.
#
# Evidence is the transcript, like unverified-done.sh: which source files the
# session wrote, and whether a review ran after the last of those writes. A
# review is a subagent whose type names a reviewer (house:reviewer, any
# *review* agent) or a review skill (code-review, security-review).
#
# Fires once per session (marker file), so being wrong costs one turn. FAIL
# OPEN: no transcript, no tool calls found, no python -- silence.
#
# shellcheck disable=SC2016
# The single-quoted block passed to `house_py -c` is python source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)

transcript=$(printf '%s' "$input" | house_json_field transcript_path)
[ -n "$transcript" ] || exit 0
[ -f "$transcript" ] || exit 0

sid=$(printf '%s' "$input" | house_json_field session_id)
[ -n "$sid" ] || sid="nosession"
state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
mkdir -p "$state_dir" 2>/dev/null
marker="$state_dir/house-unreviewed-$sid"
[ -f "$marker" ] && exit 0

report=$(house_py -c '
import json, os, re, sys

path = sys.argv[1]

CODE = os.environ.get("HOUSE_CODE_EXTS", "").split()    # from lib.sh
REVIEW = re.compile(r"review", re.I)

seq = 0
last_edit, last_review, saw_tool = -1, -1, False
edited = set()
review_ids, verdicts = {}, {}   # review tool_use id -> seq; seq -> "PASS"/"FAIL"

def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(text_of(x.get("text", "")) for x in c if isinstance(x, dict))
    return ""

def walk(node):
    global seq, last_edit, last_review, saw_tool
    if isinstance(node, dict):
        if node.get("type") == "tool_result" and node.get("tool_use_id") in review_ids:
            m = re.search(r"VERDICT:\s*(PASS|FAIL)", text_of(node.get("content")))
            if m:
                verdicts[review_ids[node["tool_use_id"]]] = m.group(1)
        if node.get("type") == "tool_use" and isinstance(node.get("input"), dict):
            saw_tool = True
            seq += 1
            name = str(node.get("name", ""))
            inp = node["input"]
            if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                p = str(inp.get("file_path") or inp.get("notebook_path") or "")
                if os.path.splitext(p)[1][1:].lower() in CODE:
                    edited.add(p)
                    last_edit = seq
            elif name in ("Agent", "Task") and REVIEW.search(str(inp.get("subagent_type") or "")):
                last_review = seq
                review_ids[node.get("id")] = seq
            elif name == "Skill" and REVIEW.search(str(inp.get("skill") or "")):
                last_review = seq
                review_ids[node.get("id")] = seq
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

try:
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

if not saw_tool or last_edit < 0:
    sys.exit(0)
# A review after the last change settles it, unless it said FAIL: then the
# findings are still sitting there unfixed.
if last_review > last_edit and verdicts.get(last_review) != "FAIL":
    sys.exit(0)

shown = sorted(os.path.basename(p) for p in edited)[:6]
more = len(edited) - len(shown)
files = ", ".join(shown) + (" and %d more" % more if more > 0 else "")
if last_review > last_edit:
    kind = "failed"
elif last_review >= 0:
    kind = "after"
else:
    kind = "none"
sys.stdout.write(kind + "\n%d source file(s) changed: %s" % (len(edited), files))
' "$transcript" 2>/dev/null) || exit 0

[ -n "$report" ] || exit 0

kind=$(printf '%s\n' "$report" | head -1)
files=$(printf '%s\n' "$report" | sed -n '2p')

: > "$marker" 2>/dev/null

{
  if [ "$kind" = "failed" ]; then
    printf 'The last review said FAIL and nothing has been fixed since:\n\n'
  elif [ "$kind" = "after" ]; then
    printf 'Code changed after the last review:\n\n'
  else
    printf 'Nobody but the author has checked this work:\n\n'
  fi
  printf '  - %s\n\n' "$files"
  printf 'House rule: work is done only after someone who did not write it has\n'
  printf 'reviewed it. Run the house reviewer agent (house:reviewer) in a fresh\n'
  printf 'context, with the user'"'"'s original request word for word, the done\n'
  printf 'checklist, and what changed. Confirm each finding before fixing it,\n'
  printf 'close the ones that do not hold up with a one-line reason, and stop\n'
  printf 'after three rounds to rethink rather than patch.\n\n'
  printf 'If this change genuinely needs no review (a one-line typo, generated\n'
  printf 'output), say so and carry on. This will not ask again this session.\n'
} >&2

exit 2
