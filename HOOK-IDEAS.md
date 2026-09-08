# Hook ideas

Candidate hooks for the `house` plugin — things that should fire everywhere,
not in one repo. Entries stay here once they ship; `done` is the record of how
an idea actually resolved, not a reason to delete it.

Status values: `open`, `in progress`, `done`, `deferred`.

The organizing principle behind every entry below: **the best hook candidates
are rules already written in `house-rules.md` that get silently ignored.** A prose
rule competes with session-level steers and loses — the session that produced
this list was itself instructed to edit files with `sed`, which the house rules
forbid outright. A hook does not lose that argument.

---

## 2026-09-07 — Hook brainstorm: preventing common Claude mistakes

> "brainstorm some hook ideas we could add across all of my repos and dev work
> that would help prevent common/obvious Claude mistakes"

Fifteen candidates, grouped by what kind of failure they catch. All follow the
existing house shape: fail open, never surface as a prompt, exit 2 with a reason
the session can act on, `#gate-ok` escape hatch where a Bash gate is involved.

### Tier 1 — existing house rules that need enforcement

**1. `no-script-splicing` — PreToolUse/Bash — `done` (2026-09-08, plugin 1.2.0)**
Refuse `sed -i`, heredoc redirects into source files, and `python -c`
string-replace when the target is a code file. The rule against this is already
explicit in `house-rules.md` and has already been overridden once by a harness-level
steer that preferred Bash for edits. The refusal names Edit/Write as the fix.
Needs an exemption for one-line appends to logs and generated text, which the
rule itself allows.

**2. `no-weakened-tests` — PostToolUse on writes — `done` (2026-09-08, plugin 1.2.0)**
Flag newly-added `.skip` / `.only` / `xfail` / `pytest.mark.skip` / `fdescribe`,
`continue-on-error: true` in workflows, and `|| true` appended to a test step.
The one failure mode where a green check actively lies — which matters more here
than elsewhere, because a green check is the substitute for reading the diff.
Must be diff-aware: fires only on lines the write introduced, or it screams on
every touch of a file that legitimately skips something.

**3. `unverified-done` — Stop — `done` (2026-09-08, plugin 1.2.0)**
If source files changed during the session and no test, build, or lint command
ever ran, say so before the session ends. Targets the most common Claude failure
of all: asserting something works without having watched it work. Once per
session, using the same marker-file pattern as `unpushed.sh`.

**4. `deny-path-scan` — PreToolUse/Bash — `done` (2026-09-08, plugin 1.2.0)**
`house-rules.md` asks the session to read `.claude/settings.json` for `permissions.deny`
entries before every recursive sweep. Nothing ever remembers to. The hook reads
it and either rewrites the command with the exclusion or refuses with the
corrected command spelled out.

**5. `stash-guard` — PreToolUse/Bash — `open`**
Block bare `git stash` / `git stash pop` when the repo has more than one
worktree. The stash stack is shared across worktrees and parallel sessions are
routine here; popping another session's work is unrecoverable.

### Tier 2 — destructive and irreversible

**6. `history-guard` — PreToolUse/Bash — `open`**
Extend `git-gate.sh` to `reset --hard`, `clean -fdx`, `checkout -- .`,
`restore .`, and `commit --amend` against an already-pushed commit. Refuses with
"make a WIP commit first" rather than a flat no, so the session has a route
forward.

**7. `commit-scope` — PreToolUse/Bash — `open`**
When a commit would stage files the session never touched — `git add -A` with
unrelated dirty files present — refuse and name them. Encodes the "don't sweep
pre-existing changes into my commit" rule, which currently depends entirely on
the session remembering to run `git status` first.

**8. `secret-write` — PreToolUse on Write/Edit and Bash — `open`**
Pattern and entropy scan for keys or tokens being written into a tracked file,
plus a block on `git add` of `.env`-shaped paths. Cheap to run, and the damage
is permanent the moment it is pushed.

### Tier 3 — output quality

**9. `machine-path-leak` — PostToolUse — `open`**
Refuse committed files containing absolute local paths (`C:/Users/Cameron/...`).
This config repo exists to be portable across machines and cloud VMs, and a
hardcoded path breaks silently on every surface except the one it was written on.

**10. `stale-model-id` — PostToolUse — `open`**
Flag writes containing Claude model IDs that no longer exist. Sessions
confidently write deprecated IDs from memory; the `claude-api` skill fixes this
only when something remembers to invoke it, which a hook does not have to.

**11. `config-parses` — extend `syntaxcheck.sh` — `open`**
Add JSON, YAML, and TOML to the parse check. A malformed `settings.json`
degrades the harness itself, and it presents as unrelated flakiness rather than
as a broken file.

**12. `conflict-markers` — PostToolUse — `open`**
Refuse a written file containing `<<<<<<<`. Trivial to implement, catches a real
and recurring class.

### Tier 4 — grounding claims in fact

**13. `capability-report` — SessionStart — `open`**
Print what the session can actually verify: browser MCP connected or not, test
command present or not, `gh` authed or not, git writes permitted or not. The
"say what you can verify" rule asks for this statement at the start of UI work,
and right now the session guesses at it. Case in point: in the session that
produced this list, the Playwright MCP server had failed to connect, and only
the raw startup output revealed it.

**14. `rule-injection` — UserPromptSubmit — `open`**
When a prompt matches something like "what changed" / "what's left" / "any open
items", inject the relevant house rule verbatim. Lets a rule be enforced at the
moment it applies rather than competing for attention inside a long `house-rules.md`.

**15. `gh-not-webfetch` — PreToolUse/WebFetch — `open`**
Redirect github.com fetches to `gh api`, per the rule about `raw.githubusercontent.com`
404s and `api.github.com` 403s being indistinguishable from an egress block.

### Suggested first batch

1, 2, 3, and 4 — every one of them a rule already written and already paid for
the hard way, and none of them satisfiable by prose.

**Shipped 2026-09-08 in plugin 1.2.0.** Notes worth keeping from building them:

- The splicing gate takes an inline interpreter's body as everything after
  `-c`/`-e` rather than as a quoted string. A balanced-quote match reads
  `python3 -c "open(\"a.js\",\"w\")..."` as ending at the first escaped quote
  and finds nothing — which is a gate that silently stops firing, the worst of
  the two failure directions.
- `sys.stdout.write(...)` is how most read-only one-liners in this repo return
  their answer, so the write detector has to look for a real file write
  (`open(..., "w")`, `write_text`, `writeFileSync`) rather than any `.write(`.
- `|| true` is a red flag on a CI step and completely ordinary in test fixture
  cleanup, so the weakened-check patterns are scoped: workflow files get the
  CI-shaped ones, test files do not.
- `unverified-done` fails open toward silence on purpose. If the transcript
  format changes and no tool calls can be found, it says nothing — the opposite
  choice would nag at the end of every session and get the hook switched off,
  taking the real catch with it.
