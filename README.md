# claude-config

Global Claude Code configuration — house rules, working preferences, and the
automatic checks that should apply everywhere, not just in one project.

This repo is two things at once:

| What | Where | Reaches |
|---|---|---|
| **House rules** | `CLAUDE.md` | This machine via symlink; cloud VMs via `cloud-setup.sh` |
| **The `house` plugin** | `plugins/house/` | Anywhere the plugin is installed or synced |
| **Harness config** | `settings.json` | This machine via symlink |

## Why a plugin

User-level configuration does not travel. Anthropic's docs are explicit about
it: *"Your user `~/.claude/CLAUDE.md` — Available in cloud sessions: No"*, and
*"If you have SessionStart hooks in your user-level `~/.claude/settings.json`,
don't expect them in the cloud."*

So the symlink-into-`~/.claude` arrangement covers exactly one Windows box.
Everything else — cloud sessions, Cowork, a fresh machine — got none of it,
which is why sessions on the web behaved differently from sessions here and
nobody could see why.

A plugin is the one artifact that installs itself into every surface from a
single source. Committing the same hooks into eight repos would also work, and
would mean eight PRs every time a rule changes.

## The `house` plugin

Four hooks, each one a bug that actually happened:

| Hook | Event | What it stops |
|---|---|---|
| `syntaxcheck.sh` | after every write | A file that no longer parses. Caught by accident last time, when `node --check` happened to run after a script ate a closing brace |
| `git-gate.sh` | before every Bash call | Force-pushes to the default branch; direct pushes that route around CI; merging a draft, a red PR, or one whose base has moved underneath it |
| `orient.sh` | session start | Answering "what changed recently" from a clone that only has `main`, and reporting a confident *nothing* while four branches sit on the remote |
| `unpushed.sh` | session end | Work left uncommitted — while staying silent when a deny rule makes committing impossible, which is what made the previous version fire uselessly at every turn |

Three commands: `/house:ship` (commit → push → PR → watch CI → merge),
`/house:since 48h` (what changed, from the remote's answer rather than the
clone's), `/house:repo-doctor` (audit a repo against the rules and open a PR for
what is missing).

**Every gate fails open.** No python, no `gh`, no network, an unfamiliar repo
shape — all of them exit 0 and let the call through. And any command containing
`#gate-ok` skips every gate. A gate that wedges a session is worse than the bug
it was watching for: the bug is occasional, the wedge is every time.

## Install

**On a machine:**

```bash
/plugin marketplace add cameron-adrian/claude-config
/plugin install house@cameron-house
```

`settings.json` already declares both, so a machine using this repo's settings
gets it without the commands above.

**In cloud sessions:** enable `house` for the claude.ai account and it loads as
`house@synced` in every cloud and Cowork session, in every repo, with no
per-repo file.

**In one repo, regardless of account settings:** commit a pointer to the repo's
own `.claude/settings.json` — `extraKnownMarketplaces` plus `enabledPlugins`, as
in this repo's `settings.json`. A pointer, not a copy, so updating the process
stays one commit here.

**The rules text in cloud VMs:** paste `cloud-setup.sh` into the Setup script
field of the cloud environment at claude.ai/code. It fetches `CLAUDE.md` into
the VM's `~/.claude/`. This requires the repo to be readable without auth.

## The symlinks

Claude Code reads `CLAUDE.md` and `settings.json` from `~/.claude/`, so each
path is a symlink into this repo. Editing either location edits the same file.

```bash
# macOS / Linux
ln -sf ~/claude-config/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/claude-config/settings.json ~/.claude/settings.json

# Windows (PowerShell, needs admin or Developer Mode)
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\CLAUDE.md" -Target "$HOME\claude-config\CLAUDE.md" -Force
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\settings.json" -Target "$HOME\claude-config\settings.json" -Force
```

## Keeping it in sync

A symlink keeps two paths on disk identical and does nothing about GitHub.

- **Machine → GitHub:** commit and push after every change. `CLAUDE.md` states
  this as a standing rule, since git history is the only record of what changed.
- **GitHub → machine:** a `SessionStart` hook runs `git pull --ff-only` on this
  repo in the background at every session start, so edits made through GitHub's
  web UI reach this machine on their own. Fail-quiet by design — no network, a
  dirty tree, diverged history all exit clean rather than breaking startup.
  Because it runs in the background, new content lands for the *next* session.
- **Plugin updates:** bump `version` in `plugins/house/.claude-plugin/plugin.json`
  on every change. Installs only pick up a new version when that field moves, so
  a forgotten bump means every machine silently keeps running the old hooks.

## Tests

```bash
bash tests/run-tests.sh
```

CI runs them on every push and PR. They are aimed at the two ways a gate fails
without anyone noticing: it stops firing on bad input, so broken code sails
through and everything *looks* fine; or it starts firing on correct input, at
which point it gets switched off and takes every other protection with it. Both
are silent, so both are tested — including the `#gate-ok` escape hatch, because
a broken escape hatch turns a wrong gate into a stuck session.

## What deliberately does NOT live here

`~/.claude/.credentials.json` holds live auth tokens and stays on the machine
only. Nothing in `~/.claude/` is committed wholesale — only the files above are
tracked, individually, so a secret cannot be swept in by accident.
