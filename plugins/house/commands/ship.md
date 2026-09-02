---
description: Commit, push, open a PR, wait for CI, and merge when green. The whole landing sequence as one command.
---

# Ship the current work

Land what is in the working tree, end to end, without stopping to ask at each
step. Do not narrate the routine parts; report at the end.

## 1. Look before committing

Run `git status` and `git diff` and read them.

Anything in there you did not write this session — generated state, a scheduled
job's output, someone else's half-finished edit — is **not yours to commit**.
Commit it separately with its own message, or leave it and say so. Never sweep
it into the same commit; the history is the only record there is, and a commit
that claims to be one change and is secretly two makes it useless.

## 2. Branch if needed

If you are on the default branch and the repo has CI, create a branch first.
A direct push to the default branch bypasses the only review this repo gets, and
the push gate will refuse it anyway.

## 3. Commit

Write the message from the diff you just read, not from the task you were given.
They differ more often than you would think — the task was the intent, the diff
is what actually happened.

Subject line says what changed. Body says why, and what would otherwise be
invisible: what was tried and rejected, what the change protects against, what a
reader would otherwise mistake it for.

## 4. Push and open the PR

```
git push -u origin <branch>
gh pr create --fill
```

Expand the body beyond `--fill` if the change needs it. Mark it **draft** if it
needs Cameron's eyes, a live test you cannot run, or anything outside git — and
say why in the body. Draft is the real gate; do not rely on anything else to
hold a PR back.

## 5. Wait for CI, properly

```
gh pr checks <number> --watch
```

Watch it. Do not poll by hand, do not sleep in a loop, and do not assume it
passed because it usually does.

If it fails: read the actual log (`gh run view --log-failed`), fix the cause,
push. Never get to green by weakening the check — not by skipping a test, not by
loosening an assertion, not by removing a step from the workflow.

## 6. Merge

Once CI is green and the PR is not draft, merge it. That is the standing rule;
it does not need confirming each time.

If the merge gate refuses, it will say why — base moved, checks pending, still
draft. Do what it says and retry. If branch protection blocks the merge outright,
say so rather than working around it.

## 7. Report

One short paragraph: what landed, the PR link, and anything you deliberately
left behind.
