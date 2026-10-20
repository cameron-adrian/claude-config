#!/bin/sh
# Stop. Refuse to end a turn that hands the user a command the session could run itself.
#
# The failure: a session finishes by telling the user to run a command, paste its
# output back, and "let me know" -- when it had a shell the whole time. Every such
# hand-off is a round trip the user pays for and the session could have skipped,
# and a prose rule against it loses to the habit. This hook does not lose that
# argument: the turn does not end.
#
# What counts as a hand-off: a `! command` line, a fenced block, or an inline
# `command` that follows "run / paste / type / execute / enter / try" -- and whose
# first word is something a session can run (python, git, curl, a script path...).
#
# What does not, because only the user can do it: a login, a password or token
# being typed, a command that starts a new session, sudo, anything destructive or
# forced, and a command with a <placeholder> only the user can fill in. A message
# that really does need the user says so with `user-only: <reason>` and passes --
# the reason is on the page, so it is checked by the person reading it.
#
# It blocks once per stop (stop_hook_active), so a wrong call costs one turn, never
# a loop. FAIL OPEN everywhere else: no transcript, no text, no python -- silence.
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

found=$(HOUSE_LAST_MESSAGE="$last" house_py -c '
import json, os, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else ""
text = os.environ.get("HOUSE_LAST_MESSAGE", "")

# The final message: the hook payload carries it on newer versions; older ones
# need the transcript. Text blocks of the last assistant entry that has any.
if not text.strip() and path and os.path.isfile(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if not isinstance(d, dict) or d.get("type") != "assistant":
                    continue
                if d.get("isSidechain"):
                    continue      # a subagent talking to the session, not to the user
                content = (d.get("message") or {}).get("content")
                if isinstance(content, str):
                    parts = [content]
                elif isinstance(content, list):
                    parts = [b.get("text", "") for b in content
                             if isinstance(b, dict) and b.get("type") == "text"]
                else:
                    parts = []
                joined = "\n".join(p for p in parts if p)
                if joined.strip():
                    text = joined
    except Exception:
        sys.exit(0)

if not text.strip():
    sys.exit(0)

# The explicit escape hatch: a stated reason that only the user can do this.
if re.search(r"user-only:\s*\S", text, re.I):
    sys.exit(0)

CONTEXT = re.compile(r"\b(?:run|paste|type|execute|enter|try)\b", re.I)

# Things only the user can do, or should not be done unasked. Searched over the
# whole line, so one such part in a chain of commands clears the lot.
USER_ONLY = re.compile(r"""
    --login\b | \blogin-[\w-]+ | \bsudo\b | add-generic-password | \bread\s+-s\b
  | \bgcloud\s+auth\b | \bgh\s+auth\b | \bpasswd\b | fallback:
  | (?<![\w./~-])(?:ssh|claude)(?![\w./-])
  | \b(?:npm|docker|aws|az)\s+login\b
  | \brm\s+-\w*r | --force\b | \bpush\s+-f\b | reset\s+--hard | \bdrop\s+(?:table|database)\b
  | <[^<>\n]{1,60}> | (?<!\S)\.\.\.(?!\S)
""", re.I | re.X)
# ssh and claude count only as a command word, never inside a path such as
# ~/.ssh or ~/claude-skills; "..." only as a stand-alone "fill this in", not a..b.

RUNNABLE = re.compile(r"""^(?:
    (?:\S*/)?(?:python3?|bash|sh|zsh|node|npx?|pytest|git|gh|ls|cat|grep|rg|find|curl|jq|bq|gcloud|
                make|launchctl|security|diff|head|tail|wc|echo|test|cd|mkdir|cp|mv|touch|sqlite3|awk|
                tar|unzip|which|pwd|env|date|stat|file|du|df|ps|lsof|plutil|defaults|osascript)
  | ~/\S+ | \./\S+ | /\S+\.(?:py|sh)
)$""", re.X)

def first_word(cmd):
    cmd = re.sub(r"^\s*(?:\$|!|>)\s*", "", cmd)
    words = cmd.split()
    while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
        words.pop(0)      # leading VAR=value assignments
    return words[0] if words else ""

def candidate_lines(block):
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        yield line

flagged = []

def is_bare_directory(line):
    # A lone path that is a folder: "started from `~/repo`", "in `./app`". It names
    # where to work, and nothing runs when a folder is typed on its own, so it is
    # not a hand-off. Only an existing folder counts: a lone script path still runs.
    cmd = re.sub(r"^\s*(?:\$|!|>)\s*", "", line).strip()
    if not cmd or re.search(r"\s", cmd):
        return False
    try:
        return os.path.isdir(os.path.expanduser(cmd))
    except Exception:
        return False

def consider(block):
    for line in candidate_lines(block):
        if USER_ONLY.search(line):
            continue
        if is_bare_directory(line):
            continue
        if RUNNABLE.match(first_word(line)):
            flagged.append(re.sub(r"^\s*(?:\$|!)\s*", "", line))

# 1. Lines that start with "!": the "run it in this session" prefix.
for m in re.finditer(r"(?m)^[ \t]*(?:\d+[.)][ \t]*|[-*][ \t]*)?!\s+(\S[^\n]*)", text):
    consider(m.group(1))

# 2. Fenced blocks that follow a run/paste/type verb.
for m in re.finditer(r"```[^\n]*\n(.*?)```", text, re.S):
    if CONTEXT.search(text[max(0, m.start() - 200):m.start()]):
        consider(m.group(1))

# 3. Inline code on a line where a run/paste/type verb comes just before it.
for m in re.finditer(r"`([^`\n]+)`", text):
    line_start = text.rfind("\n", 0, m.start()) + 1
    before = text[line_start:m.start()]
    if CONTEXT.search(before[-48:]):
        consider(m.group(1))

seen, out = set(), []
for c in flagged:
    if c not in seen:
        seen.add(c)
        out.append(c if len(c) <= 100 else c[:99] + "...")
sys.stdout.write("\n".join(out[:3]))
' "$transcript" 2>/dev/null) || exit 0

[ -n "$found" ] || exit 0

{
  printf 'You are ending the turn by asking the user to run a command you can run yourself:\n\n'
  printf '%s\n' "$found" | sed 's/^/  - /'
  printf '\nRun it now with Bash, then report the result. Do not hand it over.\n\n'
  printf 'Keep a hand-off only if it needs the user: a login or sign-in, a secret or\n'
  printf 'password to type, a command that starts a new session, something destructive\n'
  printf 'or outward-facing that needs their OK, or a value only they know. In that case\n'
  printf 'say why in the message with:  user-only: <reason>  -- and this check passes.\n'
  printf 'This will not block the same stop twice.\n'
} >&2

exit 2
