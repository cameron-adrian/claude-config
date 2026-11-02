---
description: The personal GitHub board across every repo — what needs you, what's moving, what's waiting. `start <n>` links this branch to an issue; `add <title>` files a card.
---

# The board: $ARGUMENTS

The board is plain GitHub issues and PRs across every repo the trusted owners
hold (`HOUSE_TRUSTED_OWNERS`, default `cameron-adrian`), sorted into columns by
two labels:

| Column | What puts it there |
|---|---|
| **Needs you** | `needs-me`, set by the board hook when a session stops on a `user-only:` line |
| **Doing** | `doing`, set by `/house:board start` and when the user replies to a flag |
| **In review** | an open PR |
| **To do** | an open issue with neither label |
| **Done** | closed, normally by a PR that said `Closes #n` |

Local-only work repos are never on it, and nothing here may touch one: if this
repo's `origin` is not on github.com under a trusted owner, say so and stop.

**REST only.** Cloud sessions cannot reach GitHub's GraphQL API, and `gh issue`,
`gh pr` and `gh search` use it, so every call below is `gh api` against a REST
path. Filter with `--jq` so only the fields you need come back.

## No arguments: report the board

One search per column, each `gh api -X GET search/issues -f q='<query>' -f per_page=20`,
with `user:<owner>` added for each trusted owner. The REST search refuses (422)
any query without `is:issue` or `is:pr`, so Needs you takes two searches:

1. Needs you: `is:open is:issue label:needs-me` and `is:open is:pr label:needs-me`
2. Doing: `is:open is:issue label:doing -label:needs-me`
3. In review: `is:open is:pr -label:needs-me`
4. To do: `is:open is:issue -label:doing -label:needs-me`
5. Done: `is:closed is:issue closed:>=<7 days ago, YYYY-MM-DD>`

For each **Needs you** card, fetch its newest comment that starts with
`**Needs you:**` (`gh api repos/<o>/<r>/issues/<n>/comments`) and quote that one
line, since it is the actual question. If there isn't one, use the issue body's first line.

Report in that order, **Needs you** first. Each line: `repo#n`, the title, and
how long it has been in that state, linked to the card. At most 5 per column,
newest first, with "+N more" when there are more. Skip empty columns, except
say plainly when Needs you is empty, because that is the line the user reads first.
End with the phone link for Needs you:

`https://github.com/search?q=is%3Aopen+label%3Aneeds-me+user%3A<owner>&type=issues`

## `start <n>` or `start <owner>/<repo>#<n>`: work on a card

1. `git config branch.<current branch>.house-issue <n>`, so the board hook
   flags this card, not a new one, if the session later stops to wait on the user.
2. Add `doing`: `gh api -X POST repos/<o>/<r>/issues/<n>/labels -f 'labels[]=doing'`.
   If `doing` doesn't exist yet, create it first
   (`gh api -X POST repos/<o>/<r>/labels -f name=doing -f color=0e8a16`).
3. Read the issue and its comments before starting. Earlier sessions left
   their state and the user's answers there.
4. The PR for this work says `Closes #<n>` in its body, so merging it closes the card.

## `add <title>`: file a card

`gh api -X POST repos/<o>/<r>/issues -f title='<title>'` in the current repo,
with a body that states the outcome wanted. It lands in To do. Report the link.
