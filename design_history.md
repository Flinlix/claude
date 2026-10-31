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

## 2026-10-11: Notification hooks use `-activate`, not `-sender`

The `Notification` and `Stop` hooks in `settings.json` call `terminal-notifier`
with `-activate com.anthropic.claudefordesktop`. They used `-sender` with the
same bundle id before.

**Why.** A turn ends only once every Stop hook has exited. With `-sender`,
`terminal-notifier` 2.0.0 on macOS 26.5.2 did not return: it was still running
after 20 s when killed. The "Claude is done" hook had already printed, so the
session showed a spinner with nothing happening until the hook timed out. The
same command with `-activate`, or with neither option, exited in 1 s with
status 0.

What changed on the machine to cause this was not established. The hook
configuration had not changed, so a macOS or Claude desktop update is the
likely trigger, but that is an inference.

Alternatives rejected:

- Drop the option entirely. It exits just as fast, but clicking the
  notification then does nothing. `-activate` keeps the click bringing Claude
  to the front. Neither keeps the Claude icon, which only `-sender` provided.
- Keep `-sender` and background the command or give the hook a short timeout.
  That hides the hang and leaves a stuck process behind on every turn.

## 2026-10-31: One loop per user message, consulted once

The transcripts of three projects (media-library-player, media-server,
moodle-downloader; 798 typed messages from 2026-10-09 to 2026-10-31) were read
to find how the user decides and what the configuration costs them. The
findings are in `working-style.md`, which `CLAUDE.md` now imports. This entry
records what changed in the skills and the gate, and why.

**What the transcripts showed.**

- 221 of the 798 messages were mechanical follow-ups: "split commits pre
  approved" (95), a rebuild of the zip or the app (81 and 17), "if no store
  holds" (63), starting or stopping a test server (25).
- `[Process]` was invoked once. When it presented a plan through plan mode, the
  user rejected it with "Yes, and implement everything at once". `[Stage]` was
  never invoked.
- `[Check]` was invoked more than 700 times, almost always because the gate
  required it, and most replies began with a `[Check]` line saying nothing had
  changed. The user never reacted to one.
- The user asked "what do you mean" or "explain" 11 times and "right?" or
  "correct?" 20 times, mostly after a reply used a term coined during the work
  or left open whether every requested item was done.

**`[Iterate]` replaces `[Process]`.** `[Process]` stopped after every increment
and asked the user to scope each one, which is the opposite of what the user
asked for: everything that is certain, once the plan stands, built at once, and
the user consulted once per loop. `[Iterate]` keeps the planning phase for new
work and the "define done" and invariant rules, and drops the per increment
stop and the skeleton increment. With the skeleton gone, the `// TODO`
allowances in `[Check]` and `[Split commits]` had nothing left to describe and
were removed with it (see the 2026-08-05 entry, now historical).

**`[Stage]` is deleted.** Unused, and `[Split commits]` covers it. Its German
summary was the only non-English output in the configuration, while the user
works in English throughout. Its slice rules now live in `[Split commits]`
step 3.

**`[Split commits]` commits without waiting.** The user approved every plan it
ever presented, almost always in advance. The plan is still drawn and the
held-back rules still apply; only the stop is gone.

**`[Check]` reports one line, at the end.** The review itself is unchanged.

**`[Review project]` is new.** It is the whole-project review by fresh agents
that the user requested 19 times by hand. It only reports; the caller fixes.

**The gate skips Bash-only turns that left the tree unchanged.** The 2026-08-22
entry made every Bash call arm the gate, because nothing in a command line
tells whether it wrote. That stays true, so the hook now records a fingerprint
of the working directory's git tree (the commit `HEAD` points to, the stash
list, status, both diffs, and the content hashes of untracked files) at
`UserPromptSubmit` and compares it at `Stop`. `HEAD` is part of it because a
turn that edits through Bash and then commits ends with a clean tree, which
without `HEAD` matched the start of the turn; the first version missed exactly
this, the normal end of an `[Iterate]` loop. The git calls run with
`GIT_OPTIONAL_LOCKS=0`, so that the hook never takes the index lock from a git
command running at the same time. Equal
means the Bash calls wrote nothing that git can see, and the turn is not
blocked. An edit tool still always arms the gate, and outside a repository the
behaviour is the old one.

The comparison that entry rejected ran `git status` in the hook as the only
test, for a workspace that was not a repository. Here it only relaxes the gate
where a repository exists, and falls back to blocking everywhere else.

What it costs and what it misses:

- Two fingerprints per turn. Hashing untracked files is proportional to their
  size, so a repository with large untracked files that are not ignored pays
  for them on every prompt.
- A Bash command that writes only outside the working directory's repository,
  or only into ignored files, is not seen. The previous gate caught it.
- A turn whose Bash calls changed the tree and changed it back is not blocked.
- A turn that only commits is now asked once, since `HEAD` moved.
- Edits made after `[Check]` was invoked in the same turn pass ungated, as the
  2026-08-05 entry already accepted for the settled flag. `[Iterate]` relies on
  its own step order to check the fixes a review brings.

The rationale that the hook script's comments used to carry (why a sed capture
instead of jq) is this file's: jq is not assumed to be installed, and a sed
capture costs no interpreter start on each tool call.

## 2026-10-31: Decisions after the review of the new configuration

An independent review of the configuration found contradictions between the
files. The user decided them as follows.

- **Out-of-scope fixes are allowed.** `CLAUDE.md` said to report a bug outside
  the scope and not fix it; `working-style.md` said to fix bugs and harden the
  related cases. The rule now is: fix it in a commit of its own and name it in
  the report. `[Check]` no longer calls this an exception.
- **Project facts live in the project.** The primary device, the worst cases to
  test with and the portable setup moved from `working-style.md` into a
  "Devices" section of each project's `CLAUDE.md`; the global file keeps the
  general form of each rule. `[Iterate]` step 0 lists "Devices" as part of the
  contract.
- **`[Universalize]` does not stop mid-loop.** Its step 0 questions and the size
  of its inventory go on the decision list; the sweep starts in the next loop.
- **Notifications only on a real stop.** The three `Stop` hooks ran in
  parallel, so the bell and both notifications fired even when the gate blocked
  and the turn went on. They are now one command that runs the gate first and
  notifies only when it does not block. The bell's redirection is wrapped in a
  group, because `> /dev/tty 2>/dev/null` reports its own failure before the
  `2>` applies.
- **Commits carry no trailers**, also outside the commit skills.

## 2026-10-31: The hand-back format, tested against every past round

Four independent readers went through all 1,706 rounds of the four coding
sessions (827 with a real reply from the user) and tested a proposed
table-based hand-back against each kind of round. The result replaced the
"How to report" and "Visuals" sections of `working-style.md`.

**The largest failure was not the format.** In 119 of the 827 rounds (14 %) the
last message was a `[Check]` line or an automated notice, and the real report
stood above it; seven answers never reached the user. Hence rule 1: the last
message is the complete hand-back, `[Iterate]` checks before it reports, and a
check the gate forces afterwards repeats the hand-back's first line and open
decisions.

**One fixed block list fits only building rounds** (about 40 %). Questions,
commit or server rounds, reviews, debugging and planning each need their own
blocks, so the format is a set of rules for every hand-back plus a table of
blocks per kind of round.

**What the user's replies showed.**

- Follow-up questions came from: a rule's status given without where it was
  verified (a status from tests alone was contradicted on the iPhone three
  times), items without a done or proposed status, assumptions placed at the
  end, coined terms, mechanisms instead of effects, unstated scope, and no
  machine named for a limit.
- Short stable IDs were answered at once every time; IDs that repeated across
  rounds caused confusion.
- In visual choices the user picked a non-recommended option in five of seven
  cases, so distinct options matter more than the recommendation.
- Local image paths were not opened, and a canvas that did not open in the
  Claude app was asked to be republished. Pictures are therefore always
  Artifacts.
- Never referenced in 827 replies: test counts, commit hashes, zip sizes and
  checksums, the check's file lists. Arrow and tree diagrams were never needed;
  scenario tables did that job.

The status markers (✓ ◐ ✗ ?) and the Artifact rule were the user's choice
between the alternatives of words and of pictures only on request.
