#!/bin/sh
# PreToolUse on Bash. Refuses to let a shell command rewrite a code file.
#
# The house rule says structural edits go through Edit and Write, and it exists
# because a merge conflict resolved with a python string-replace silently ate a
# function's closing brace. Edit fails loudly when its target does not match; a
# script writes the damage and returns zero.
#
# The reason this is a hook and not just prose: the rule loses arguments. A
# session-level steer that says "prefer Bash for file changes" sits closer to
# the model's attention than a line in CLAUDE.md, and the splice happens anyway.
# A gate does not lose that argument.
#
# Deliberately narrow. Only three shapes, and only when the thing being written
# is a *code* file:
#   - sed/perl in-place editing
#   - a heredoc redirected into one
#   - an inline python/node/perl script that opens one for writing
# Appending a line to a log, building a commit message with a heredoc, piping a
# heredoc into an interpreter for a computation -- all untouched. A gate that
# fires on correct input is the failure mode that gets gates deleted, and this
# one sits on every single Bash call.
#
# Escape hatch: `#gate-ok` anywhere in the command, same as git-gate.sh.
#
# shellcheck disable=SC2016
# The single-quoted block passed to `house_py -c` is python source. Nothing in
# it is meant to expand.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
cmd=$(printf '%s' "$input" | house_json_field tool_input.command)

[ -n "$cmd" ] || exit 0
case "$cmd" in *'#gate-ok'*) exit 0 ;; esac

# Cheap bail before starting an interpreter: if none of the three shapes can
# possibly be present, there is nothing to look at.
case "$cmd" in
  *sed*|*perl*|'<<'*|*'<<'*|*python*|*node*) ;;
  *) exit 0 ;;
esac

verdict=$(printf '%s' "$cmd" | house_py -c '
import re, sys

cmd = sys.stdin.read()
if not cmd or len(cmd) > 20000:
    sys.exit(0)

# What counts as code. Markdown, text, logs, csv and rst are deliberately absent:
# they have no brace or indent structure to silently destroy, and appending to
# one is the exemption the house rule itself grants.
CODE = (
    "js mjs cjs jsx ts tsx py sh bash zsh rb go rs java kt swift "
    "c h cc cpp hpp cs php lua sql json yml yaml toml html css scss "
    "vue svelte astro tf gradle ps1 psm1"
).split()
EXT = r"\.(?:%s)\b" % "|".join(CODE)

def code_files(text):
    return re.findall(r"[\w./\\@$~-]+" + EXT, text)

hits = []

# ---------------------------------------------------------------- sed -i
# Both spellings, and both `-i` alone and bundled into a flag cluster (-ri).
for m in re.finditer(r"\bsed\b([^|;&\n]*)", cmd):
    seg = m.group(1)
    if re.search(r"(?:^|\s)--in-place\b|(?:^|\s)-[a-zA-Z]*i(?:\b|\.)", seg):
        for f in code_files(seg):
            hits.append(("sed -i", f))

for m in re.finditer(r"\bperl\b([^|;&\n]*)", cmd):
    seg = m.group(1)
    if re.search(r"(?:^|\s)-[a-zA-Z]*i", seg):
        for f in code_files(seg):
            hits.append(("perl -i", f))

# ------------------------------------------------------------- heredocs
# Only when the heredoc is redirected INTO a code file. `cat > f.py <<EOF` and
# `cat <<EOF > f.py` are the same thing in different orders, so the redirect
# target is looked for across the whole command rather than adjacent to the <<.
# A heredoc piped to git commit -F -, or into an interpreter, has no such
# target and is left alone.
if re.search(r"<<-?\s*[\"\x27]?\w+", cmd):
    for m in re.finditer(r">>?\s*([\w./\\@$~-]+" + EXT + ")", cmd):
        hits.append(("a heredoc redirected into", m.group(1)))

# --------------------------------------------- inline interpreter writes
# The specific thing that ate the closing brace: read a source file, do a string
# replacement, write it back. Requires an actual write indicator, so the many
# read-only `python -c` one-liners (json.load, a version lookup) stay silent.
#
# The body is taken as everything after the -c/-e rather than as a quoted
# string, because the quoting inside one of these is exactly what a regex
# cannot follow: `python3 -c "open(\"a.js\",\"w\")..."` ends its first quoted
# run at the backslash-escaped quote, and a balanced-quote match reads the body
# as `open(\` and finds nothing.
for m in re.finditer(r"\b(?:python3?|py|node|perl)\b[^|;&\n]*?(?:-c|-e)\s(.*)",
                     cmd, re.S):
    body = m.group(1)
    # An actual file write, not any write at all. `sys.stdout.write(...)` is
    # how half the read-only one-liners in this repo print their answer, and
    # flagging those would make the gate unusable.
    writes = re.search(
        r"open\s*\([^)]*[\x27\"][rab+]*w|"
        r"write_text\s*\(|writeFileSync|appendFileSync|createWriteStream|"
        r"fileinput\.\w*\(?[^)]*inplace",
        body)
    if writes:
        for f in code_files(body):
            hits.append(("an inline script writing", f))

if not hits:
    sys.exit(0)

seen, lines = set(), []
for kind, f in hits:
    if (kind, f) in seen:
        continue
    seen.add((kind, f))
    lines.append("  - %s %s" % (kind, f))

sys.stdout.write("\n".join(lines))
' 2>/dev/null) || exit 0

[ -n "$verdict" ] || exit 0

house_deny "This command edits a code file through the shell:

$verdict

House rule: structural changes go through the Edit and Write tools, never sed,
a heredoc, or an interpreter string-replace. The reason is not neatness -- Edit
fails loudly when its target does not match, while a script writes the damage
and returns zero. A conflict resolved this way once ate a function's closing
brace and nothing caught it.

Use Edit for a change to an existing file, Write for a whole new one. If this
genuinely is not a structural edit -- appending one line to a generated file,
say -- add \`#gate-ok\` to the command and it will run as written."
