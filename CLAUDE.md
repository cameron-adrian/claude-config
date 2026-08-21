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
