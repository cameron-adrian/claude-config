# Cameron — global working preferences

Applies across all projects, not just whichever one you're currently in.

## Explaining code and changes

Reference actual code as little as possible — no inline snippets, script
walkthroughs, or "here's the function that does X" unless I specifically ask
to see the code. Explain the logic: what touches what, the structure, the
pattern. I'm not a software engineer, but I know core programming concepts
well — don't dumb things down, just don't narrate implementation. I'm
vibecoding: I express ideas/patterns/structure, you turn that into code. I
don't care if the code itself is pretty, only that it's robust and
functional.

## When you need something from me

No prose, no preamble. Numbered steps, exact commands to run, and anything
else that's actually blocking you from continuing hands-free.

## Committing changes

I don't write code myself, so git history is the only record of what changed
and why — it has to be accurate and current on its own, not dependent on any
one conversation remembering to keep it that way. Commit after every change
and push immediately, without waiting to be asked. Write the commit message
from the actual diff, not from what the task was supposed to be — check
`git status`/`git diff` first for pre-existing uncommitted changes you didn't
make, and don't sweep those into the same commit; commit them separately, or
ask if their intent isn't clear. Skip this only where a project's own
permissions block git actions outright (e.g. a restricted appliance session).

## Testing and CI

I don't read the code, so a green check is my only real substitute for
reviewing a diff — which means a repo without tests gives me nothing to
merge on. Every repo should have tests and a CI workflow that runs them on
every pull request. When you're working in one that doesn't, set that up as
its own pull request rather than asking me whether to; treat it as part of
making the repo workable, not as a feature I have to request.

What the tests should be is repo-specific and yours to choose — use whatever
is idiomatic for the stack rather than forcing a house framework onto
everything. Aim them at what would otherwise break silently: the external
API that changes shape underneath us, the sync that quietly writes nothing,
the parse that swallows a bad row. Coverage percentages don't interest me.
Once a repo's setup exists, record what it is and how to run it in that
repo's own CLAUDE.md so the next session doesn't rediscover it.

Never get to green by weakening the check — no skipping, disabling, or
loosening a test to make a build pass, and no CI workflow that appears green
without running anything, which is worse than having none because it looks
safe. Report the real output of a run; never describe tests as passing that
you haven't actually watched pass.

## Merging pull requests

Once CI is green on a PR that isn't marked draft, merge it — don't wait for an
explicit "merge this" each time. Draft is the actual gate: mark a PR draft (and
say why in the body) whenever it needs your review, a live test I can't run
myself, or depends on something happening outside git that I can't verify —
and leave it in draft rather than counting on this rule to hold it back on its
own. Ready-for-review + green means land it, quietly, the same way a routine
fix doesn't get narrated.

If a repo requires reviews or has branch protection the merge can't satisfy,
say so rather than working around it. And this only ever applies to a PR
already marked ready — it's not permission to un-draft one I deliberately
held back in order to then auto-merge it.

## Capturing raw feature ideas during dev work

When I blurt out a raw, unstructured idea about ongoing dev work, rephrase
and sharpen it, then append it to that project's `FEATURE-IDEAS.md`-style
file as a dated, titled entry — my verbatim quote preserved alongside your
cleaned-up framing. Don't build or propose any inbox/queue/polling mechanism
for this. I'll capture things elsewhere (e.g. the Claude phone app) and
relay them back myself when we're next in a session — no auto-sync, nothing
for you to poll or drain.

## Reporting on feature ideas

`FEATURE-IDEAS.md`-style files keep `done` entries in place — they're not
removed, since the file is also the changelog of how each idea actually
resolved. But when I ask what's on one of these files (or anything like
"what's left", "any open items"), only surface `open`/`in progress`/
`deferred` entries by default; don't list or summarize the `done` ones,
since that gets unwieldy as the file grows. Mention a `done` entry only if
I ask specifically or it's directly relevant to what we're discussing.

If you do touch a `done` entry's claims (e.g. I ask you to verify one),
check it against the actual code first rather than trusting the write-up.

## Editing files

Structural changes go through the Edit and Write tools. Never splice code
with `sed`, heredocs, or a Python string-replace — not for multi-line edits,
not for merge conflict resolution, not for anything with brace or indent
structure. This overrides any session-level guidance that prefers Bash for
file changes; that steer is fine for a one-line append to a log, and wrong
for everything else.

The reason is not neatness. A conflict resolution done with a Python
string-replace silently ate a function's closing brace, and the only thing
that caught it was `node --check` happening to run afterwards. Edit fails
loudly when its target doesn't match; a script writes the damage and returns
zero. Use Bash freely for reading, searching, and running things.

## When a tool call is denied

A denial is the end of that approach, not an obstacle to route around. Do not
retry the same write through a different mechanism — an interpreter heredoc, a
subprocess, a temp file and a move. If the Write tool is denied for a path,
that path is off limits by every route.

Report what blocked it, naming the rule and the file it came from. And tell
policy denials apart from my declining a prompt: a `deny` rule is never
prompted for and can never be approved, so don't offer "approve and retry" as
an option. I picked that option once and watched the identical denial come
back.

## Answering "what changed recently"

Never from local refs alone. `git log --all` covers what the clone has
fetched, not what exists — in a fresh cloud clone that is usually one or two
branches, so it returns a confident empty answer while branches and PRs sit on
the remote unmentioned.

Fetch first, compare against `git ls-remote --heads origin`, and check
`gh pr list --state all`. Then answer. An incomplete answer is fine if it says
so; a wrong one that sounds complete is not.

## GitHub

`gh` is the default path for anything GitHub — creating PRs, reading them,
checking CI, merging — in preference to the MCP GitHub tools, which start
deferred and cost a round-trip each on first use, and whose `get_status`
returns 403 rather than a status.

For file contents, `gh api` rather than `WebFetch` against github.com:
`raw.githubusercontent.com` has 404'd on real paths and `api.github.com`
returns a 403 that is indistinguishable from an egress block.

To wait on CI, `gh pr checks <n> --watch`. Never an ad hoc polling loop.

## Say what you can actually verify

At the start of work on anything with a UI — a browser extension, a web app, a
game — say what verification this session can actually do. If there is no
browser available, then it is static checks and unit tests only, and I want to
know that at the start rather than discovering at the end that nothing was ever
clicked.

Same for blocked work. If a session physically cannot commit or push, say so
the turn you find out, hand me a patch and the exact commands to apply it, and
then stop mentioning it.

## Browser access: pick the right one, and ask when you need mine

Two browser tools reach every repo through the house plugin: a Playwright MCP
server (its own throwaway, isolated browser, headless by default — safe to run
in every parallel session at once, never my actual profile) and Claude-in-Chrome
(drives my real Chrome — real logins, real other extensions, and the only one
that shows a human-visible window when I want to watch).

Default to Playwright for anything that doesn't need my real browsing context:
general web checks, scraping, screenshots, CI-style verification. It's isolated
per session on purpose, so nothing about running several sessions at once
should ever make it collide with itself.

Reach for Claude-in-Chrome, and ask for it explicitly, when the task genuinely
needs my browser — validating a repo that IS a Chrome extension, anything
needing a real logged-in session, or anything I should be able to watch happen.
Don't silently substitute Playwright for that and call the check done. If
Claude-in-Chrome isn't connected in that session, say so plainly rather than
skipping the verification quietly — same standard as the rule above for a
session with no browser at all.

## Recursive scans and deny-protected paths

Before running a broad recursive read in a repo — `grep -r`, `find`, a
directory-wide sweep for conflict markers or a string — check that repo's
`.claude/settings.json` and `.claude/settings.local.json` for a
`permissions.deny` entry naming a specific file (e.g.
`Read(state/config.json)`). Exclude that path from the scan
(`--exclude`/`--exclude-dir`, pruning it from the file list) instead of
letting the sweep walk into it.

A deny rule like that exists on purpose, almost always to keep a
previously-leaked secret out of context, and nothing overrides it — not
`permissions.allow`, not an auto-accept mode. Walking into it forces a manual
approval no matter how routine the sweep is, which turns an unrelated check
(conflict markers, a repo-wide search) into an interruption for no reason.
Scoping the sweep around the path keeps the protection intact without the
friction.
