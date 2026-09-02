#!/bin/sh
# PostToolUse on Write|Edit|MultiEdit|NotebookEdit.
#
# Parses whatever was just written and, if it does not parse, hands the error
# straight back to the session. Exit 2 on a PostToolUse hook shows stderr to
# Claude; the write has already happened, so nothing is blocked and nobody is
# prompted -- the session simply learns it broke the file and fixes it.
#
# This exists because a session hand-splicing a merge conflict with a python
# string-replace ate a function's closing brace, and the only reason anyone
# found out was that `node --check` happened to run shortly afterwards. The
# check should not be a happy accident.
#
# Deliberately syntax only. No type checking, no linting: tsc is far too slow to
# sit in the path of every edit, and a linter's opinions are not what this is
# for. The bar is "does this file still parse", nothing more.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
f=$(printf '%s' "$input" | house_json_field tool_input.file_path)

[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

fail() {
  printf 'The file you just wrote does not parse:\n\n%s\n\n%s\n' \
    "$1" \
    "Fix $f before going any further -- it is broken on disk right now." >&2
  exit 2
}

case "$f" in
  *.js|*.mjs|*.cjs|*.jsx)
    command -v node >/dev/null 2>&1 || exit 0
    out=$(node --check "$f" 2>&1) || fail "$out"
    ;;

  *.py)
    # compile() rather than py_compile, so the check leaves no __pycache__
    # behind. A syntax gate that dirties the working tree would get itself
    # switched off inside a week.
    out=$(house_py -c '
import sys
p = sys.argv[1]
src = open(p, encoding="utf-8").read()
compile(src, p, "exec")
' "$f" 2>&1)
    rc=$?
    [ "$rc" = 127 ] && exit 0
    [ "$rc" = 0 ] || fail "$out"
    ;;

  *.json)
    out=$(house_py -c '
import sys, json
json.load(open(sys.argv[1], encoding="utf-8"))
' "$f" 2>&1)
    rc=$?
    [ "$rc" = 127 ] && exit 0
    [ "$rc" = 0 ] || fail "$out"
    ;;

  *.yml|*.yaml)
    # PyYAML is not guaranteed anywhere, so a missing import is a skip, not a
    # failure. Exit 3 is the script's own signal for "no parser available".
    out=$(house_py -c '
import sys
try:
    import yaml
except ImportError:
    sys.exit(3)
yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
' "$f" 2>&1)
    rc=$?
    case "$rc" in
      0|3|127) ;;
      *) fail "$out" ;;
    esac
    ;;

  *.sh)
    out=$(sh -n "$f" 2>&1) || fail "$out"
    ;;
esac

exit 0
