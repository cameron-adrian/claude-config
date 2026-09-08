# Working in claude-config itself

Project memory for this repo only. The house rules that apply everywhere live
in `house-rules.md`, which is symlinked to `~/.claude/CLAUDE.md` and therefore
already loaded in this session as user memory — do not restate or duplicate any
of it here.

> **If you are reading this file in a repo that is not `claude-config`, the
> symlink is stale.** It should point at `house-rules.md`, not at this file.
> Say so to Cameron immediately: until it is repointed, every session on this
> machine is running without the house rules. The fix is in the README, under
> "The symlinks".

## What this repo is

Two artifacts from one source: the house rules text (`house-rules.md`) and the
`house` plugin (`plugins/house/`). The rules reach this machine by symlink and
cloud VMs by `cloud-setup.sh`; the plugin reaches everything else by being
installed. `README.md` explains the why and the install paths in full.

**Editing `~/.claude/CLAUDE.md` and editing `house-rules.md` here are the same
act** — same file, two paths. There is no separate copy to keep in step, and no
reason to ever write to the `~/.claude` path directly.

## Tests

```bash
bash tests/run-tests.sh
```

Plain bash, no framework. Needs `python`, `node`, and `curl` on PATH; the suite
degrades gracefully and says so when `node` or `curl` is missing rather than
skipping silently. CI runs it on **Ubuntu and Windows** on every push and PR,
plus `shellcheck -e SC1091` over every shell script in the repo.

The suite is aimed at the two ways a gate fails invisibly: it stops firing on
bad input, or it starts firing on good input and gets switched off. Both
directions get an assertion. **When you add a check here, mutation-test it** —
break the thing it watches, watch it go red, then revert. A check that cannot
fail is worse than none, because it reads as coverage.

## Two things that must move together

- **`plugins/house/**` and `version` in `plugins/house/.claude-plugin/plugin.json`.**
  Installs only pick up new hook code when that field moves, so a change
  without a bump ships to nobody while looking merged. `ci/require-version-bump.sh`
  enforces this on every PR.
- **`.claude-plugin/marketplace.json` and `plugins/house/.claude-plugin/plugin.json`
  descriptions.** Two hand-maintained copies of the same text; the marketplace
  one is what shows at install time. The suite asserts they match.

`cloud-setup.sh` is a third: it fetches `house-rules.md` by hardcoded URL, so
renaming that file silently strips the rules from every future cloud session.
The suite guards the URL.

## Where ideas go

`HOOK-IDEAS.md` is this repo's `FEATURE-IDEAS.md`-style file — candidate hooks
for the plugin. `done` entries stay in place as the record of how each resolved,
so the house rule about reporting on such files applies: surface `open`,
`in progress` and `deferred` by default, not `done`.

## Git quirks specific to this checkout

- **`main` is permanently checked out in the primary worktree**, so
  `gh pr merge --delete-branch` fails on its local step *after the merge has
  already landed*. Merge without that flag, then `git push origin --delete <branch>`.
- **Merges here are squashes**, so a branch cut from a pre-merge tip shows as
  conflicted against `main` even when the content is identical. Rebase onto
  `origin/main`.
- **Other sessions hold locked worktrees** under `.claude/worktrees/`. Their
  branches cannot be deleted and should not be forced; leave them alone.
- Local `main` in the primary checkout self-heals via the `SessionStart` pull
  hook in `settings.json`, in the background, so it lands for the *next*
  session — it is normal for it to look stale mid-session.

## Not committed, ever

`~/.claude/.credentials.json` holds live auth tokens. Nothing in `~/.claude/`
is committed wholesale — only the individually tracked files above — so a
secret cannot be swept in by accident.
