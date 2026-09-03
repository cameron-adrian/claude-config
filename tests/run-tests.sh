#!/usr/bin/env bash
# Regression suite for the house plugin's hooks.
#
# What these are aimed at: the two ways a gate fails without anyone noticing.
# It stops firing on bad input, so broken code sails through and the gate looks
# like it is working because nothing complains. Or it starts firing on good
# input, at which point it gets switched off and every protection goes with it.
# Both are silent, so both get a test.
#
# Run:  bash tests/run-tests.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPTS="$ROOT/plugins/house/scripts"
PASS=0
FAIL=0

# Same interpreter resolution the hooks use. Git Bash on Windows has `py` and
# `python` but no `python3`; the CI runner has `python3`. Hard-coding either one
# makes the suite pass on one machine and error on the other.
PY_BIN=""
for c in python3 python py; do
  command -v "$c" >/dev/null 2>&1 && { PY_BIN="$c"; break; }
done
[ -n "$PY_BIN" ] || { echo "no python interpreter found; cannot run tests" >&2; exit 1; }

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# Run a hook script with a JSON payload, capturing rc, stdout, stderr.
run_hook() {
  _script="$1"; _payload="$2"
  printf '%s' "$_payload" | bash "$SCRIPTS/$_script" >/dev/null 2>"$TMP/stderr"
  HOOK_RC=$?
  HOOK_ERR=$(cat "$TMP/stderr" 2>/dev/null)
  return 0
}

expect_rc() {
  if [ "$HOOK_RC" = "$1" ]; then pass "$2"; else fail "$2" "expected rc=$1, got rc=$HOOK_RC"; fi
}

# `[ x ] && pass || fail` reads like if-then-else and is not: it binds left to
# right, so a non-zero pass would run fail too. These two say what was meant.
expect_empty() {  # $1=actual  $2=name
  if [ -z "$1" ]; then pass "$2"; else fail "$2" "got: $1"; fi
}

expect_eq() {  # $1=expected  $2=actual  $3=name
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected $1, got $2"; fi
}

TMP=$(mktemp -d)
# Windows sometimes still holds a handle on the fixture repos at exit; a noisy
# cleanup failure must not look like a test failure.
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

printf '\n== static checks ==\n'

for s in "$SCRIPTS"/*.sh "$ROOT/cloud-setup.sh" "$ROOT/tests/run-tests.sh"; do
  if sh -n "$s" 2>"$TMP/e"; then
    pass "parses: $(basename "$s")"
  else
    fail "parses: $(basename "$s")" "$(cat "$TMP/e")"
  fi
done

for j in "$ROOT/.claude-plugin/marketplace.json" \
         "$ROOT/plugins/house/.claude-plugin/plugin.json" \
         "$ROOT/plugins/house/hooks/hooks.json" \
         "$ROOT/settings.json"; do
  if "$PY_BIN" -c "import json,sys;json.load(open(sys.argv[1]))" "$j" 2>"$TMP/e"; then
    pass "valid json: $(basename "$(dirname "$j")")/$(basename "$j")"
  else
    fail "valid json: $j" "$(cat "$TMP/e")"
  fi
done

# Every hook the manifest wires up must actually exist. A renamed script with a
# stale manifest entry is the classic way a gate silently stops running.
"$PY_BIN" - "$ROOT/plugins/house/hooks/hooks.json" >"$TMP/manifest-scripts" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
for _, entries in d["hooks"].items():
    for e in entries:
        for h in e["hooks"]:
            m = re.search(r'scripts/([a-z-]+\.sh)', h["command"])
            if m:
                print(m.group(1))
PY

# tr strips the carriage returns python adds when it writes text on Windows;
# without it every name reads as "orient.sh\r" and no file ever matches.
while read -r s; do
  s=$(printf '%s' "$s" | tr -d '\r')
  [ -n "$s" ] || continue
  if [ -f "$SCRIPTS/$s" ]; then pass "manifest points at a real script: $s"
  else fail "manifest points at a real script: $s" "missing"; fi
done <"$TMP/manifest-scripts"

printf '\n== syntaxcheck: must fire on broken input ==\n'

cat >"$TMP/broken.js" <<'EOF'
function hello() {
  return 1;
EOF
if command -v node >/dev/null 2>&1; then
  run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/broken.js\"}}"
  expect_rc 2 "broken JS is reported"
  case "$HOOK_ERR" in *"does not parse"*) pass "broken JS names the problem";;
    *) fail "broken JS names the problem" "stderr was: $HOOK_ERR";; esac
else
  printf '  skip node not installed; JS checks not exercised here (CI has node)
'
fi

printf 'def f():\nreturn 1\n' >"$TMP/broken.py"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/broken.py\"}}"
expect_rc 2 "broken Python is reported"

printf '{"a": 1,}\n' >"$TMP/broken.json"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/broken.json\"}}"
expect_rc 2 "broken JSON is reported"

printf 'if [ 1 = 1 ]; then\n' >"$TMP/broken.sh"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/broken.sh\"}}"
expect_rc 2 "broken shell is reported"

printf '\n== syntaxcheck: must stay silent on good input ==\n'

printf 'function hello() {\n  return 1;\n}\n' >"$TMP/ok.js"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/ok.js\"}}"
expect_rc 0 "valid JS passes"
expect_empty "$HOOK_ERR" "valid JS says nothing"

printf 'def f():\n    return 1\n' >"$TMP/ok.py"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/ok.py\"}}"
expect_rc 0 "valid Python passes"

# The gate must not dirty the working tree, or it gets turned off.
if [ -d "$TMP/__pycache__" ]; then
  fail "python check leaves no __pycache__" "it created one"
else
  pass "python check leaves no __pycache__"
fi

printf '{"a": 1}\n' >"$TMP/ok.json"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/ok.json\"}}"
expect_rc 0 "valid JSON passes"

printf 'anything at all\n' >"$TMP/notes.txt"
run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/notes.txt\"}}"
expect_rc 0 "unknown extension is skipped"

run_hook syntaxcheck.sh "{\"tool_input\":{\"file_path\":\"$TMP/does-not-exist.js\"}}"
expect_rc 0 "missing file is skipped"

run_hook syntaxcheck.sh '{"tool_input":{}}'
expect_rc 0 "payload with no path is skipped"

run_hook syntaxcheck.sh 'not json at all'
expect_rc 0 "unparseable payload is skipped"

printf '\n== git-gate ==\n'

# A fixture repo with CI and a remote, so the gate has something real to read.
REPO="$TMP/repo"
mkdir -p "$REPO/.github/workflows"
(
  cd "$REPO" || exit 1
  git init -q -b main .
  git config user.email t@t.t
  git config user.name t
  printf 'name: c\non: [push]\n' >.github/workflows/c.yml
  git add -A
  git commit -qm init
  git remote add origin "$TMP/fake-remote.git"
  # Fabricate the remote-tracking ref the gate reads, without needing a network.
  git update-ref refs/remotes/origin/main HEAD
) >/dev/null 2>&1

gate() { ( cd "$REPO" && printf '%s' "$1" | bash "$SCRIPTS/git-gate.sh" 2>/dev/null ); }

out=$(gate '{"tool_input":{"command":"git push --force origin main"}}')
case "$out" in *'"deny"'*) pass "force-push to default is refused";;
  *) fail "force-push to default is refused" "got: $out";; esac

out=$(gate '{"tool_input":{"command":"git push origin main"}}')
case "$out" in *'"deny"'*) pass "direct push to default in a CI repo is refused";;
  *) fail "direct push to default in a CI repo is refused" "got: $out";; esac

# The escape hatch has to work, or a wrong gate becomes a stuck session.
out=$(gate '{"tool_input":{"command":"git push origin main #gate-ok"}}')
expect_empty "$out" "#gate-ok overrides the gate"

out=$(gate '{"tool_input":{"command":"git push -u origin my-feature"}}')
expect_empty "$out" "push to a feature branch is allowed"

out=$(gate '{"tool_input":{"command":"ls -la"}}')
expect_empty "$out" "unrelated commands are ignored"

out=$(gate '{"tool_input":{"command":"git status"}}')
expect_empty "$out" "read-only git commands are ignored"

# Fail-open: no repo at all must not block anything.
out=$(cd "$TMP" && printf '{"tool_input":{"command":"git push origin main"}}' | bash "$SCRIPTS/git-gate.sh" 2>/dev/null)
expect_empty "$out" "fails open outside a git repo"

# Fail-open: a repo with no CI gets no push gate, because there is no check to
# protect in the first place.
NOCI="$TMP/noci"
mkdir -p "$NOCI"
(
  cd "$NOCI" || exit 1
  git init -q -b main .
  git config user.email t@t.t
  git config user.name t
  git commit -q --allow-empty -m init
  git remote add origin "$TMP/fake2.git"
  git update-ref refs/remotes/origin/main HEAD
) >/dev/null 2>&1
out=$(cd "$NOCI" && printf '{"tool_input":{"command":"git push origin main"}}' | bash "$SCRIPTS/git-gate.sh" 2>/dev/null)
expect_empty "$out" "no CI means no push gate"

printf '\n== payload cwd wins over ambient shell cwd ==\n'

# The bug this guards: two Bash tool calls that each start with `cd <repo>`
# can share one persistent shell, so a hook can fire while the shared shell's
# directory is still mid-transition from a *different*, concurrently-running
# command. That let a claude-config merge get evaluated against job-search's
# repo by ambient accident, find job-search's own draft PR under the same
# number, and refuse a perfectly mergeable claude-config PR because of it.
#
# Both cases below deliberately mismatch the ambient shell cwd against the
# payload's own cwd field, and assert the payload wins.

# Ambient = NOCI (no CI, ungated); payload cwd = REPO (has CI, gated). If the
# hook were still trusting ambient cwd, this push would sail through silently.
out=$(cd "$NOCI" && printf '{"tool_input":{"command":"git push origin main"},"cwd":"%s"}' "$REPO" | bash "$SCRIPTS/git-gate.sh" 2>/dev/null)
case "$out" in *'"deny"'*) pass "payload cwd overrides an ambient no-CI directory";;
  *) fail "payload cwd overrides an ambient no-CI directory" "got: $out";; esac

# Ambient = REPO (has CI, gated); payload cwd = NOCI (no CI, ungated). If the
# hook were still trusting ambient cwd, this push would be refused when it
# shouldn't be.
out=$(cd "$REPO" && printf '{"tool_input":{"command":"git push origin main"},"cwd":"%s"}' "$NOCI" | bash "$SCRIPTS/git-gate.sh" 2>/dev/null)
expect_empty "$out" "payload cwd overrides an ambient CI directory"

printf '\n== blocked-permission detection ==\n'

. "$SCRIPTS/lib.sh"

BLK="$TMP/blocked"
mkdir -p "$BLK/.claude"
cat >"$BLK/.claude/settings.json" <<'EOF'
{"permissions":{"deny":["Bash(git commit *)","Bash(git push *)"]}}
EOF
if ( cd "$BLK" && house_git_blocked >/dev/null ); then
  pass "a deny on git commit is detected"
else
  fail "a deny on git commit is detected" "it was not"
fi

OKD="$TMP/allowed"
mkdir -p "$OKD/.claude"
cat >"$OKD/.claude/settings.json" <<'EOF'
{"permissions":{"allow":["Bash(git commit *)"],"deny":["Read(state/config.json)"]}}
EOF
if ( cd "$OKD" && house_git_blocked >/dev/null ); then
  fail "an allow-only settings file is not treated as blocked" "it was"
else
  pass "an allow-only settings file is not treated as blocked"
fi

printf '\n== stop hook ==\n'

(
  cd "$REPO" || exit 1
  printf 'dirty\n' >dirty.txt
) >/dev/null 2>&1

export CLAUDE_PLUGIN_DATA="$TMP/plugindata"
out_rc=$( cd "$REPO" && printf '{"session_id":"s1"}' | bash "$SCRIPTS/unpushed.sh" >/dev/null 2>&1; echo $? )
expect_eq "2" "$out_rc" "uncommitted work is flagged once"

out_rc=$( cd "$REPO" && printf '{"session_id":"s1"}' | bash "$SCRIPTS/unpushed.sh" >/dev/null 2>&1; echo $? )
expect_eq "0" "$out_rc" "it does not fire twice in one session"

# The failure this hook was rewritten for: demanding a commit that policy forbids.
mkdir -p "$REPO/.claude"
cp "$BLK/.claude/settings.json" "$REPO/.claude/settings.json"
out_rc=$( cd "$REPO" && printf '{"session_id":"s2"}' | bash "$SCRIPTS/unpushed.sh" >/dev/null 2>&1; echo $? )
expect_eq "0" "$out_rc" "silent when commit and push are denied"
rm -f "$REPO/.claude/settings.json"

printf '\n== orientation ==\n'

out=$( cd "$REPO" && printf '{"session_start_reason":"startup"}' | bash "$SCRIPTS/orient.sh" 2>/dev/null )
case "$out" in *"Branch:"*) pass "reports the branch";; *) fail "reports the branch" "got: $out";; esac
case "$out" in *"uncommitted"*) pass "reports uncommitted work";; *) fail "reports uncommitted work" "got: $out";; esac

out=$( cd "$TMP" && printf '{}' | bash "$SCRIPTS/orient.sh" 2>/dev/null )
expect_empty "$out" "says nothing outside a git repo"

printf '\n----------------------------------------\n'
printf '%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
exit 0
