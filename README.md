# claude-config

Global Claude Code configuration — house rules, working preferences, and
harness settings that should apply everywhere, not just one project.

Two files live here, and both are the source of truth for this machine:

| File | What Claude Code uses it for |
|---|---|
| `CLAUDE.md` | User-level memory — instructions loaded into every session, in every project |
| `settings.json` | User-level harness config — hooks, permissions, model/UI preferences |

Claude Code reads them from `~/.claude/`, so each path is a **symlink** into
this repo. Editing either location edits the same file, in both directions.

```bash
# macOS / Linux
ln -sf ~/claude-config/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/claude-config/settings.json ~/.claude/settings.json

# Windows (PowerShell, may need admin or Developer Mode enabled)
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\CLAUDE.md" -Target "$HOME\claude-config\CLAUDE.md" -Force
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\settings.json" -Target "$HOME\claude-config\settings.json" -Force
```

If symlinking isn't possible on a given machine, copy the files into
`~/.claude/` by hand and remember to re-copy after edits.

## Keeping this in sync with GitHub

A symlink only keeps the two *paths on disk* identical — it does nothing about
GitHub. That needs commits, in both directions:

- **Machine → GitHub:** commit and push after every change. `CLAUDE.md` states
  this as a standing rule, since git history is the only record of what changed.
- **GitHub → machine:** a `SessionStart` hook in `settings.json` runs
  `git pull --ff-only` on this repo in the background at every session start,
  so edits made through GitHub's web UI reach this machine on their own. It's
  fail-quiet by design (no network, dirty tree, diverged history — all exit
  clean rather than breaking session startup). Because it runs in the
  background, new content lands for the *next* session, not the one pulling it.

## What deliberately does NOT live here

`~/.claude/.credentials.json` holds live auth tokens and stays on the machine
only. Nothing in `~/.claude/` is committed wholesale — only the two files above
are tracked, individually, so a secret can't be swept in by accident.
