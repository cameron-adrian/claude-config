---
description: Audit this repo against the house rules — tests, CI on PRs, a CLAUDE.md that records how to run them, the house plugin pointer — and open a PR for what is missing.
---

# Repo doctor

Audit the current repo against the standing rules, then fix what is missing.
Report findings before changing anything.

## What to check

**1. Tests exist.** Whatever is idiomatic for the stack — no house framework
forced onto anything. If there are none, that is the finding.

**2. CI runs them on every pull request.** A workflow with `on: [push,
pull_request]` that actually invokes the suite. Two specific failure shapes to
look for, both worse than having no CI at all:

- a workflow that appears green without running anything
- a suite that is present but not wired into the workflow

**3. The repo's own `CLAUDE.md` records the test command** and how to run the
app. If the setup exists but is undocumented, the next session rediscovers it
from scratch.

**4. The house plugin pointer** is present in `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "cameron-house": {
      "source": { "source": "github", "repo": "cameron-adrian/claude-config" }
    }
  },
  "enabledPlugins": { "house@cameron-house": true }
}
```

Merge into the existing file rather than overwriting it — a repo may have
permissions or hooks of its own that must survive.

**5. No `.claude/settings.json` deny rule that confines ordinary work.** Deny
rules apply to *every* session in the repo, and a cloud session always starts at
the repo root, so an "escape hatch" that depends on starting one directory up
does not exist there. A committed deny on `Bash(git commit *)` or
`Bash(git push *)` means no cloud session can ever land anything — that has
already cost a full session's work once.

**6. `FEATURE-IDEAS.md` exists** if the repo is one where ideas get captured.
Do not create one speculatively.

## What tests to write, if you are writing them

Aim at what breaks silently, not at coverage:

- the external API that changes shape underneath us
- the sync that quietly writes nothing
- the parse that swallows a bad row
- the scheduled job that keeps exiting 0 while doing nothing

That last one is not hypothetical. A pipeline ran green for three weeks —
scheduler happy, exit 0, output file current — while nothing consumed its
output at all. Every signal it emitted was about whether the *producer* ran.

Coverage percentages are not interesting.

## How to land it

One PR per concern. Missing tests and missing CI go together; the plugin pointer
is its own small PR. Never weaken a check to get to green.

Report what you found in the other repos' terms too, if asked for a sweep: which
repos are missing what, so the gaps are visible without opening each one.
