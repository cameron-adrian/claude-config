---
description: What changed in a time window (e.g. /house:since 48h) across every branch and PR, not just the ones this clone happens to have.
---

# What changed since $ARGUMENTS

Answer for the window in `$ARGUMENTS` — `48h`, `3 days`, `last week`, a date.
Default to 48 hours if nothing was given.

## Get the truth first — this is the whole point of the command

A session was asked this exact question, ran `git log --all --since=...` in a
fresh clone that held only `main`, got nothing back, and reported that nothing
had been pushed. There were four branches and three open PRs, one of them with
ten commits from that same day.

`--all` means *every ref this clone has fetched*, not every ref that exists. In
a cloud session the clone is usually `main` plus one working branch, so `--all`
is close to meaningless and fails silently rather than loudly.

So, in order, before looking at any log:

```
git fetch --all --prune --tags
git ls-remote --heads origin
gh pr list --state all --limit 50
```

Compare `ls-remote` against local `refs/remotes/origin/*`. If anything is
missing, fetch it. Only once the clone actually holds what the remote holds does
a log query mean anything.

## Then report

Group by branch and by PR, and for each: what changed and why, in terms of
behaviour rather than files touched. Include merged PRs, open PRs, and any
branch pushed inside the window that has no PR — that last category is the one
people forget exists, and it is where half-finished work hides.

Explain the logic and the shape of what changed. Do not paste code or walk
through scripts.

## If asked to review it

Resolve the window to a commit range and hand that range to `/code-review`
explicitly:

```
/code-review <base-sha>...<head-sha>
```

Pass a range, never a bare PR number — the review command has been observed
ignoring a PR-number argument and silently reviewing the working diff instead,
which produces a confident review of entirely the wrong changes. If you do want
a PR reviewed, fetch and check out its branch first and pass `main...HEAD`.
