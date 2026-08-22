# Design history

Why the configuration in this repository is shaped the way it is. Code comments
explain how something works; this file records why it was chosen, and what was
rejected on the way.

## 2026-08-05: The check gate settles when `check` is invoked, not when it finishes

`hooks/check-gate.sh` blocks the `Stop` event when a turn modified files without
running the `check` skill. Two flag files per session resolve it,
`check-pending-<id>` and `check-settled-<id>`.

**Why a settled flag exists at all.** `check` repairs what it finds, so it edits
files itself, and those edits raise `check-pending` again. With only the pending
flag the same turn would block forever: block, `check` runs, `check` edits,
block again. `settled` records that the gate is resolved for this turn, whether
it was resolved by blocking once or by `check` having run.

**Why `settled` is raised on invocation.** `PostToolUse` on the `Skill` tool is
the earliest signal that `check` was entered, and for a skill that runs inline
in the main loop, no hook event marks the point where it finished. The
consequence is accepted rather than overlooked: a turn that invokes `check` and
then abandons it settles the gate all the same. The gate enforces that `check`
is entered, not that it is carried through. Enforcing the latter would need an
end-of-skill event that does not exist.

Alternatives rejected:

- Have the `check` skill write the settled flag itself. A skill is a prompt, not
  a program, so nothing guarantees the write happens. The hook is the only
  mechanism the model cannot quietly skip.
- Decide at `Stop` time by reading the transcript the payload points at, looking
  for a `check` invocation since the last user message. The information is
  there, but it costs locating the turn boundary and parsing the transcript
  format, and it breaks whenever either changes. A flag the hook writes itself
  carries the same fact without reading anything.
- Let the gate block once per turn and leave it at that, which is what the
  repository actually did until today. Every turn that edited a file was then
  blocked once even when `check` had already run, spending a turn on a review
  that had already happened.

**Correction.** Commit 57bac70 added the `satisfied` mode to the script and
described it in the script header, but never registered the matching hook in
`settings.json`. The mode was unreachable, and the header documented behaviour
the configuration did not implement. Commit 2d286e4 registers `PostToolUse` on
the `Skill` tool, which makes the header accurate.

**Why the payload is inspected rather than trusted.** The `Skill` matcher fires
for every skill, so `satisfied` confirms `"skill": "check"` in the payload
before settling. Without that guard, invoking any skill at all would clear the
gate.

## 2026-08-05: An increment may be a skeleton that does not build

`[Process]` step 2 used to require a minimal MVP that worked end to end. It now
accepts a skeleton instead: signatures, types and call structure in place, with
bodies left empty behind a `// TODO`.

**Why the skeleton need not build.** Requiring it to build sounds harmless and
is not. In any language where an empty body is a type error, a function with a
declared return type among them, "it must build" forces a fabricated return
value into every stub. That is the one thing a skeleton must not do, because it
makes unwritten code read as written. Letting the tree not build keeps the gap
honest and visible.

**What replaces "it builds" as the rule.** Nothing may be *accidentally*
broken. A marked gap is not breakage; a call site left dangling by a rename is.
That distinction is what `[Stage]` now enforces in place of the old
completeness test, and it is the reason a skeleton is still stageable.

**Why `[Check]` and `[Stage]` changed too.** Neither is decoration. `[Check]`
is told to fix everything it finds and never defer, so it would have
implemented the very bodies the increment deliberately left empty. `[Stage]`
required a slice to build before it could be staged, so a skeleton could never
have been committed. The allowance in `[Process]` is inert unless both give way,
so all three moved together.

**Why the user scopes each increment (step 1).** Step 0 still agrees the whole
plan, and the plan still names every increment through to done. What it cannot
fix is where one increment stops, which is a judgement about how much
unfinished work is acceptable right now. That belongs to the user, so each
increment opens with a question round and is scoped by the answers rather than
by the original request alone. The plan is the map; step 1 fixes the detail.

Alternatives rejected:

- Require the skeleton to build, which would have left `[Stage]` untouched. It
  buys a tidier tree at the cost of fake implementations, and the fake is worse
  than the broken build because it is silent.
- Drop the complete up-front plan and decide everything increment by increment.
  Asking each time then has no map to ask against, and the answers stop
  composing into a whole.

The hand-back block gained a `TODO` line so the bodies left empty in an
increment are stated when it is handed over, not discovered later.

## 2026-08-22: The check gate asks whenever a write was possible

`hooks/check-gate.sh` armed itself from `PostToolUse` on
`Edit|Write|NotebookEdit`. It therefore measured which tool wrote a file, not
whether a file was written.

**How it failed.** Counting tool calls in the transcripts for
`~/personal_assistant`: the session of 2026-08-21 made 9 edit-tool calls and was
blocked 3 times, while three sessions on 2026-08-22 made 0 edit-tool calls
against 839 `Bash` calls and were blocked 0 times. Those turns still rewrote
project files, through `sed -i`, through heredocs, and in one case by writing a
Python script into the scratchpad and running it. `check` ran 4 times across the
three sessions, never once because the gate required it.

**Why the trigger is coarse.** `Bash` joined the matcher with no inspection of
the command. Nothing in a command line settles whether a file was written:
`python3 edit1.py` is how one of those sessions edited its project and is also
how it ran its tests. The hook does not need to settle it, because `[Check]`
opens by establishing scope from `git status` and `git diff`, which report
modifications, deletions, renames, and mode changes alike. So the hook asks and
the skill answers, each at the level where the information exists.

**What that costs.** A turn that ran only read-only Bash now ends with a `check`
that reports nothing changed. The skill's scope step used to answer an unchanged
tree by reviewing the whole repository, which would have turned every such turn
into a full review, so it now stops in one line instead. The cost is accepted:
the alternative is the hook re-deriving a judgement git already makes, and
making it worse.

**Why `Bash` rather than every turn.** A turn that called no write-capable tool
cannot have written, and blocking it would spend a `check` on conversation.

Alternatives rejected:

- Grep the Bash command for a write pattern. `python3 edit1.py` defeats it, and
  the pattern would have to keep pace with every way a shell can write a file.
- Scan the session directory for files whose mtime is newer than a stamp taken
  at `UserPromptSubmit`. This was built and measured before it was dropped: it
  cost 40 ms over the 923 files of `~/personal_assistant`. It needed a prune
  list per project, covering build products, tooling caches, and everything
  Claude Code writes inside `~/.claude`, and testing it showed it blind to
  renames, deletions, and mode changes, since `mv` preserves mtime and a
  deletion leaves nothing to stat. Those are exactly the changes `git status`
  reports plainly. Two mechanisms answering one question, the cheaper one also
  being the blinder.
- Compare `git status --porcelain` inside the hook. `~/personal_assistant` is
  not a repository, it contains four, and it would run one level below the skill
  that already makes that call.

The 7-day expiry of orphaned flag files moved from `mark` to `reset`. With
`Bash` in the matcher `mark` fires on nearly every tool call, and the sweep
belongs where it runs once per turn.
