# claude-config

Global Claude Code configuration — house rules and working preferences that
should apply everywhere, not just one project.

`CLAUDE.md` here is the source of truth. On each machine, Claude Code reads
its user-level memory from `~/.claude/CLAUDE.md`, so that path should be a
symlink into this repo:

```bash
# macOS / Linux
ln -sf ~/claude-config/CLAUDE.md ~/.claude/CLAUDE.md

# Windows (PowerShell, may need admin or Developer Mode enabled)
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\CLAUDE.md" -Target "$HOME\claude-config\CLAUDE.md" -Force
```

If symlinking isn't possible on a given machine, copy `CLAUDE.md` to
`~/.claude/CLAUDE.md` by hand and remember to re-copy after edits.
