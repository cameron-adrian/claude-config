#!/bin/sh
# Stop. Refuse to end a turn while the work is visibly unfinished.
#
# Most of what the user says to a session is "keep going": test it properly,
# finish the checklist, do the obvious next thing. Each of those is a turn the
# session ended too early. Two signals, both read from the session itself:
#
#   1. Open items on the session's own checklist. The house rule is that a task
#      starts by writing down what done means as a task list (TaskCreate /
#      TaskUpdate, or TodoWrite in older sessions). A pending or in-progress item
#      at the end of a turn is work the session said it would do and has not.
#   2. A turn that ends by offering the next step as a question ("Want me to run
#      the tests?", "Should I continue?"). If the answer is obviously yes and it
#      is not one of the user-only items, asking is the early stop.
#
# A message with `user-only: <reason>` passes: being blocked on the user is a
# legitimate place to stop. It blocks once per stop (stop_hook_active), so a wrong
# call costs one turn, never a loop. FAIL OPEN otherwise: no transcript, no text,
# no python, an unfamiliar transcript shape -- silence.
#
# shellcheck disable=SC2016
# The single-quoted block passed to `house_py -c` is python source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)

active=$(printf '%s' "$input" | house_json_field stop_hook_active)
case "$active" in True|true|1) exit 0 ;; esac

transcript=$(printf '%s' "$input" | house_json_field transcript_path)
last=$(printf '%s' "$input" | house_json_field last_assistant_message)

report=$(HOUSE_LAST_MESSAGE="$last" house_py -c '
import json, os, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else ""
text = os.environ.get("HOUSE_LAST_MESSAGE", "")

tasks = {}          # TaskCreate id -> [subject, status]
pending_ids = {}    # TaskCreate tool_use id -> subject, until its result names the task
todos = None        # the last TodoWrite snapshot, if any
last_text = ""
# Open items only count when the session was working its checklist in THIS
# turn. A user who asks something new mid-task ("where do we stand?") gets an
# answer, not a session dragged back onto the old list.
event = turn_start = last_task = 0

def is_prompt(d, content):
    # A real user prompt: text or images typed by the user. Not tool results,
    # not hook feedback or other meta entries, not task notifications.
    if d.get("type") != "user" or d.get("isMeta"):
        return False
    if isinstance(content, str):
        return not content.lstrip().startswith("<task-notification>")
    if isinstance(content, list):
        kinds = {b.get("type") for b in content if isinstance(b, dict)}
        return bool(kinds & {"text", "image"}) and "tool_result" not in kinds
    return False

def content_text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text")
    return ""

if path and os.path.isfile(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if not isinstance(d, dict) or d.get("isSidechain"):
                    continue    # a subagent checklist is not the session checklist
                content = (d.get("message") or {}).get("content")
                event += 1
                if is_prompt(d, content):
                    turn_start = event
                if d.get("type") == "assistant":
                    t = content_text(content)
                    if t.strip():
                        last_text = t
                if not isinstance(content, list):
                    continue
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        name, inp = b.get("name"), b.get("input") or {}
                        if not isinstance(inp, dict):
                            continue
                        if name in ("TaskCreate", "TaskUpdate", "TodoWrite"):
                            last_task = event
                        if name == "TaskCreate":
                            pending_ids[b.get("id")] = str(inp.get("subject") or "")
                        elif name == "TaskUpdate":
                            tid, st = str(inp.get("taskId") or ""), inp.get("status")
                            if tid in tasks and st:
                                if st == "deleted":
                                    del tasks[tid]
                                else:
                                    tasks[tid][1] = st
                        elif name == "TodoWrite" and isinstance(inp.get("todos"), list):
                            todos = [(str(x.get("content") or ""), x.get("status"))
                                     for x in inp["todos"] if isinstance(x, dict)]
                    elif b.get("type") == "tool_result" and b.get("tool_use_id") in pending_ids:
                        subject = pending_ids.pop(b.get("tool_use_id"))
                        m = re.search(r"Task #(\w+) created", content_text(b.get("content")))
                        if m:
                            tasks[m.group(1)] = [subject, "pending"]
    except Exception:
        sys.exit(0)

if not text.strip():
    text = last_text
if not text.strip():
    sys.exit(0)

# Blocked on the user is a legitimate place to stop.
if re.search(r"user-only:\s*\S", text, re.I):
    sys.exit(0)

OPEN = ("pending", "in_progress")
open_items = [s for s, st in tasks.values() if st in OPEN]
if todos is not None:
    open_items += [s for s, st in todos if st in OPEN]
if last_task <= turn_start:
    open_items = []     # the checklist was not touched this turn

# An offer of the next step in the closing lines of the message. Two shapes: a
# question ("Want me to...?", "Should I...?"), which only counts when the
# sentence really is a question, and the statement form ("Let me know if you
# would like me to...", "Happy to... if you want").
ASKED = re.compile(r"""
    \b(?:want\s+me\s+to | should\s+i | shall\s+i | would\s+you\s+like\s+me\s+to
       | do\s+you\s+want\s+me\s+to | would\s+you\s+like\s+(?:me\s+)?to\s+(?:run|test|continue|proceed)
    )\b""", re.I | re.X)
STATED = re.compile(r"""
    \b(?:(?:let\s+me\s+know|tell\s+me)\s+if\s+you(?:\x27d|\s+would)?\s+(?:like|want)\s+(?:me\s+)?to
       | (?:i\s+can|happy\s+to)\s+[^.?!\n]{0,80}\bif\s+you(?:\x27d)?\s+(?:like|want)
    )\b""", re.I | re.X)
tail = text.strip()[-320:]
closing = re.split(r"(?<=[.!?])\s+|\n+", tail)
closing = [s.strip() for s in closing if s.strip()][-2:]
# "?" may hide behind markdown or a closing bracket: **Want me to run it?**
offer = next((s for s in closing
              if (ASKED.search(s) and s.rstrip("*_`)]}\x22 ").endswith("?"))
              or STATED.search(s)), "")

out = []
for s in open_items[:5]:
    out.append("open: " + (s if len(s) <= 90 else s[:89] + "..."))
if len(open_items) > 5:
    out.append("open: ...and %d more" % (len(open_items) - 5))
if offer:
    out.append("offer: " + (offer if len(offer) <= 140 else offer[:139] + "..."))
sys.stdout.write("\n".join(out))
' "$transcript" 2>/dev/null) || exit 0

[ -n "$report" ] || exit 0

opens=$(printf '%s\n' "$report" | sed -n 's/^open: //p')
offer=$(printf '%s\n' "$report" | sed -n 's/^offer: //p')

{
  printf 'The work is not finished, so the turn is not over.\n\n'
  if [ -n "$opens" ]; then
    printf 'Your checklist still has open items:\n'
    printf '%s\n' "$opens" | sed 's/^/  - /'
    printf '\nDo them now and mark each one completed. An item that turned out to\n'
    printf 'be obsolete or superseded gets marked completed or deleted, with a word\n'
    printf 'on why in your message.\n\n'
  fi
  if [ -n "$offer" ]; then
    printf 'You ended by offering the next step instead of taking it:\n'
    printf '  "%s"\n\n' "$offer"
    printf 'If it is reversible and in scope (testing, verifying, finishing,\n'
    printf 'fixing what review found), do it now. Decide, do not ask.\n\n'
  fi
  printf 'Stop only for something that needs the user: a sign-in, a secret,\n'
  printf 'money, something destructive or outward-facing, or a value only they\n'
  printf 'know. Then say so with:  user-only: <reason>  -- and this check passes.\n'
  printf 'This will not block the same stop twice.\n'
} >&2

exit 2
