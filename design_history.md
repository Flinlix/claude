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

## 2026-10-31: Automatic pull of the configuration, and a notification whenever it is the user's turn

**Pull at session start.** `hooks/pull-config.sh` runs on `SessionStart` for
new and resumed sessions. It starts `git pull --ff-only` in the background and
returns at once, because the hooks documentation says a session's first answer
waits for its `SessionStart` hooks, and a pull over a slow network would
otherwise hold it. The pull therefore lands after the session has loaded its
configuration and takes effect from the next session on. Only fast-forwards are
taken, so a machine with local commits or edits is never merged or overwritten;
such a pull fails instead. Each result is written to `state/config-pull.log`,
and the next session's hook prints a failure into that session's context so
that it is reported to the user once. `GIT_TERMINAL_PROMPT=0` keeps a missing
credential from waiting for input.

**One notifier for every wait.** `hooks/notify-user.sh` rings the terminal bell
and shows a desktop notification through terminal-notifier, else the built-in
`osascript` on macOS, else `notify-send` on Linux, so the same configuration
works on a machine without Homebrew. Clicking it brings back the app the
session runs in: macOS passes the starting app's bundle identifier to its child
processes as `__CFBundleIdentifier` (`com.microsoft.VSCode` in the VS Code
extension). This replaces the fixed `-activate com.anthropic.claudefordesktop`
of the 2026-10-11 entry, which brought up the Claude app even for a session in
VS Code.

It is called from three events:

| Event | When | Message |
|---|---|---|
| `Stop`, after the check gate lets the turn end | Claude has finished | "Your turn: Claude is done" |
| `PreToolUse` on `AskUserQuestion` and `ExitPlanMode` | a question or a plan waits for an answer | "Your turn: Claude has a question" |
| `Notification` of type `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` | a permission or input dialog | the notification's own text |

The documentation does not say whether the question dialog or the plan approval
fires a `Notification` event, so both are caught through their tools. A
`Notification` arrives about 6 s after its dialog, so for that event alone the
notifier stays silent when the same session was notified within the last 15 s;
the other two events always notify. `idle_prompt` is left out because it
repeats the `Stop` notification 60 s later.

Not covered: cloud sessions on claude.ai/code do not read the local
`~/.claude/settings.json`, so neither hook runs there.

## 2026-10-31: A weekly review of the configuration

The user asked for proposed changes to the configuration "from time to time",
timed to Saturday, or to Sunday when Saturday had none.

**How it is timed.** `hooks/config-review-due.sh` runs on `SessionStart`. On a
Saturday or Sunday, when the last review is two days old or more, it tells the
session that the review is due; `[Iterate]` then runs `[Review config]` before
its report, and the proposals join that report's Decisions. Two days separate
the cases the user named: a review on Saturday is less than two days old for
the whole Sunday, and the previous weekend's review is always older. The
review writes `state/config-review-last` itself, so a session that is told and
ends without reviewing leaves it due for the next session.

Alternatives rejected: a scheduled cloud agent, because cloud sessions cannot
read the local transcripts the review is built on; a local timer running Claude
headless, because it would act unattended with tool access; a review at the
end of every loop, which the user did not pick.

**What it reads.** `skills/review-config/extract_rounds.py` writes every round
since the last review (the hand-back the user saw and the reply they typed),
the same extraction the 2026-10-31 format test used. Proposals carry their exact
wording and their evidence, default to "skip", and are applied only after the
user picks them.

The stamp lives in `state/`, which is not versioned, so each machine keeps its
own: a machine reviews its own transcripts, which are not versioned either.

The first review is due on 2026-11-07; this entry's session served as the
review for 2026-10-31.

## 2026-10-31: Project contracts are kept current through a limited dialog

The user asked that project-specific `CLAUDE.md` or `AGENTS.md` files be
written without being asked for, but that every change be asked first in a
choice dialog, at most one every five turns.

**Which file.** `AGENTS.md` is read by other coding agents as well, so when a
project has one it holds the contract and `CLAUDE.md` imports it; otherwise
the contract is `CLAUDE.md`, as in the three projects that have one.

**Why a dialog, against "consult once per loop".** The user asked for a dialog
explicitly; `working-style.md` names it as the one exception.

**How the limit is enforced.** `hooks/contract-dialog.sh` counts user turns per
session on `UserPromptSubmit`, and records the turn of every `AskUserQuestion`
whose question header is `Contract` on `PostToolUse`. On the four turns after
a contract dialog it tells the session that none is allowed and how many turns
remain; on the other turns it prints nothing, so that the allowed case, which
is the common one, adds nothing to the context. The header is the marker
because it is a field of the tool's input the hook can read, and the question
text is free prose. A turn counts once the user submits a message; a question
answered inside a dialog or a hook continuation is not a turn.

Not enforced by the hook: two contract dialogs within one allowed turn. The
rule in `working-style.md` says one dialog per allowed turn, and a dialog holds
up to four questions, which leaves no reason for a second.

## 2026-10-31: UI text may ask questions

The rule "UI text gives instructions, not questions" under "The UI tells the
truth" in `working-style.md` is removed at the user's request. UI text may
again be phrased as a question where that reads better.

## 2026-11-01: A part is ruled out only by measuring its effect

Added to the "Bug with an unclear cause" default in `working-style.md`, from the
first weekly configuration review. In the flip-dot work of 2026-10-14 to
2026-10-20 the Pi side was declared proven four times (rounds 15, 25, 49 and 64)
on the strength of register readbacks: the UART and the pad control showed the
pin being driven low. The fault was the Pi's own GPIO14, whose driver could not
pull the line low (round 104). Reading the pad input against the opposite pull
resistor exposed it at once. What a part was told to do says nothing about what
it did, so the rule asks for the effect measured at the receiving side.

Considered and dropped in the same review: repeated "Should I?" questions
mid-loop and pictures sent as terminal text, both from before this configuration
was installed and both covered by rules that exist now; the scratchpad being
emptied by reboots, which is particular to one machine and went into that
project's contract instead.

## 2026-11-04: The configuration names no machine of the user's

The configuration is pulled onto every machine a session runs on, so a rule
written for one of them is wrong on the others. `working-style.md` said the
round's page is opened "in the user's browser on the Mac (`open <file>`)". A
session on a Linux server, reached from the Mac through an editor, has no `open`
and no way to reach the Mac's browser, so it could follow neither half. The rule
now names the operating system's own command for opening a file, and says that
a session on another machine than the one the user sits at only names the path.

Two examples went for the same reason: "which Moodle courses" named one
project's data, and "iPhone ?" one device. They read "which accounts or records"
and "phone ?" now.

The rule examples under "What matters most" went the same way, at the user's
request. "no store", "never unenroll" and "only one ffmpeg at a time" named one
project's term, one project's operation and one product; they read "nothing on
disk", "never delete a remote record" and "only one encoder at a time". The list
of guarded actions, "enroll, unenroll, register, delete or overwrite", was the
same project's vocabulary and reads "create, change, delete or overwrite". The
status example follows the first rule. "The slider always reflects the
position" was already general and stays.

The hooks needed no change:
`notify-user.sh` already chooses its notifier by what the system has, and it is
the implementation's own file, which may name the platforms it handles. The
dated entries above keep the machines they were written about.

## 2026-11-04: Decisions after the review of the first sessions on the server

From a review of the 16 rounds of 2026-11-04. Applied:

- **`[Check]` runs before the hand-back** (`working-style.md`, hand-back rule 1).
  In two rounds the check ran after the hand-back and changed what it had
  reported: a rewrap of edited notes, and a heading and an unsupported date
  claim on a research page. Each forced check also showed the hand-back twice.
- **A session on another machine serves the page** (`working-style.md`, "The
  round's page"). Naming the path left the user to open a scratchpad file
  through the editor. The page is now served on the machine's network address
  and the server stops when the next page replaces it. While it runs, anyone
  on that network can read the page. The terminal and the final message name
  the address in place of the path.
- **Change requests start the loop** (`CLAUDE.md`). `[Iterate]` was invoked in
  none of the 16 rounds, and one round left its fix uncommitted against
  "commits are decided alone".
- **A contract the user asked for needs no dialog** (`working-style.md`,
  "Project contracts"). The rule asked for a dialog before creating any
  contract, also when the user's message had asked for the contracts outright.

Rejected:

- **Relaxing the check gate outside a repository** (C1). Three of seven forced
  checks followed turns that changed nothing, all in a working directory that
  is not a repository. The user kept the gate as it is.
- **Answering small rounds in the terminal** (C3). Three of four built rounds
  did so against the rule; the rule stays.

## 2026-11-04: A contract holds only what stays true

Added to "Project contracts" in `working-style.md`, at the user's request. The
first contracts written for a set of projects held lines that were true only on
the day: a package's former name, "no test covers this module", "no remote",
an install hint drawn from one stale environment, and a machine fault that the
parent folder's contract already stated. Each would have become wrong or
redundant without anything failing. The rule names the three kinds that do not
belong (current state, history, repetition) and where each goes instead.

## 2026-11-04: A contract names nothing local to one machine

Added to "Project contracts" in `working-style.md`, at the user's request. The
project contracts named the development environment by its conda name and
pointed to "the contract of the folder above this repository", both true only
on the machine they were written on, and committed into repositories that are
cloned elsewhere. The rule keeps what the repository's own files require, such
as a compose file that builds from sibling repositories, because that holds on
every machine the repository is used on.

A fact that is true of one machine alone goes into that machine's memory for
sessions, which is local by construction. The contract of the folder holding
the repositories, in no repository, had held such facts; it was deleted the
same day.

## 2026-11-04: Worst cases are not part of a contract

At the user's request, a project contract no longer lists worst cases, and the
definition of a contract in `working-style.md` and in `[Iterate]` no longer asks
for them. The first contracts showed why: nearly every worst case they listed
restated the project's README or design notes, which is the repetition the rule
above already keeps out. "It feels instant and smooth" now asks for the hardest
case the change itself can meet instead of the cases a contract names.

The same day, all contracts written that day were deleted at the user's
request, from the working trees and from the unpushed history, and the facts
they held about one machine moved into that machine's memory for sessions.

## 2026-11-04: A contract is proposed only when the work shows a rule

With every contract deleted, the rule that every project has one would have
made the next session in each project propose a new one at once. At the user's
choice the mechanism stays, but a contract, or a missing part of one, is
proposed only when the work has shown a rule worth writing down.

## 2026-11-07: Weekly review: check gate, check message, plain words

The review of 91 rounds since 2026-11-04 found four recurring faults, and the
user chose to fix all of them.

- **The check gate fired on read-only turns.** Sessions ran in the folder that
  holds the repositories, which is no repository itself, so every shell command
  counted as a write: 10 turns that only read or served a page were forced into
  a check that found nothing. Outside a repository the gate now compares the
  repositories directly below the session's folder. A shell command that
  writes only outside those repositories, such as a page in the scratchpad, is
  no longer gated; edits with the edit tools still always are.
- **The check's message displaced the result.** 13 hand-backs began with the
  check's own line and 10 with a note that there was nothing to check, against
  the rule that the first line is the result. A check forced after the
  hand-back now starts with the hand-back's first line, and says nothing when
  nothing changed.
- **Commits and pushes waited on a request for a summary.** The user asked 5
  times for the changes in plain words before approving. Such a decision now
  always comes with that list.
- **Hand-backs used names from the code.** 7 follow-ups asked for a simpler
  explanation. Rule 7 now asks for each line to be read as someone who has not
  seen the code.

## 2026-11-07: A structural rethink every 10 turns

The user asked, once per project so far, whether the whole structure still
makes sense, with several fresh agents, and then asked for that question to
become a skill that runs on its own every 10 turns.

- **`[Rethink]` beside `[Review project]`.** The review looks for defects in
  the tree as it is; the rethink asks whether each part should exist and be
  shaped this way: merge, split, remove, or a different core approach. The two
  questions draw different findings, so they stay two skills.
- **Triggered by a hook, not by an instruction.** `hooks/rethink-due.sh` counts
  user turns per session, as `contract-dialog.sh` does, and speaks only on every
  10th turn, so the other turns carry nothing extra in their context. A
  rule in the instructions would rely on the session counting its own turns.
- **Its report joins the loop's report.** A due rethink runs besides the user's
  request, so the user still gets one hand-back per turn.
- **A proposal that reopens a recorded decision is marked and never
  recommended.** The first run proposed rendering the whole conversation every
  turn, which the user had ruled out.

## 2026-11-07: Weekly review, second run

167 rounds in seven folders since the last review. The user applied three of
the proposals.

- **The ship step was skipped after small fixes.** In one project the user
  typed "build" or "rebuild" 11 times, each after a hand-back saying the commit
  was not built yet. `[Iterate]` step 7 now runs the ship step in every loop
  that committed a change to what it builds.
- **Which deliverable is current was unclear.** Two follow-ups asked whether
  the app and the disk image, or both PDFs, were up to date. The state line now
  names each deliverable.
- **Background agents left the user asking for progress.** Three follow-ups in
  one session. A hand-back given while an agent runs now names what it does,
  how far it is and when it should finish.
- A fourth finding, the forced check placing its line before the result, was
  already fixed by the review of the same day.

## 2026-11-07: Simple terms, and large changes recommended when better

The user asked that every response be in simple terms and that a large change
be recommended without hesitation when it is better. In the same round the
user chose six options that had been marked as reopening a recorded decision
and so had not been recommended. `working-style.md` now asks for simple terms
in every reply, page and decision (rule 10) and says the recommended option is
the better one whatever its size; `[Rethink]` marks a proposal that reopens a
recorded decision with that decision but may recommend it.


## 2026-11-08: Whole reviews and rethinks only on request

The user asked that a whole-project review or a rethink start only when they
ask for one, and that neither be proposed otherwise. A critical change still
gets one review agent on its own.

- **The rethink hook is removed.** `hooks/rethink-due.sh` and its
  `UserPromptSubmit` entry are deleted; the 2026-11-07 entry on a rethink every
  10 turns is historical. `[Rethink]` keeps its method and runs on request.
- **`[Iterate]` step 6 no longer runs `[Review project]`.** The trigger was the
  number of files changed, which says little about risk. It is replaced by one
  fresh read-only agent on the loop's diff, started only for a critical change:
  one that touches a contract rule or its enforcement, deletes or overwrites
  data or writes to another system, or touches credentials, permissions or
  network exposure. One agent on the diff costs a fraction of a whole review
  and looks where a defect would do the most harm.
- **The rule lives in `working-style.md`.** Its decision table says when either
  whole review runs; `[Iterate]` step 6 defines a critical change and carries
  out the single review.
- **The weekly configuration review is unchanged.** It reviews the
  configuration, not a project; whether it should also wait for a request is
  left to the user.

## 2026-11-08: A skill that distills a project

The user asked to make "extract and generalize the rules and edge cases, and
name the outliers" a skill, after it was done once by hand for
raspi-initializer. `[Distill]` collects with three fresh read-only agents
(stated rules, rules only in the code, edge cases), because one reader anchored
on the contract misses what only the code enforces. It groups rules into five
to nine principles and edge cases into kinds of trouble, and sorts every
outlier as real (a decision with a fix), apparent (the principle is reworded)
or accepted by a recorded decision (never reopened unmarked). It proposes only;
writing principles into a contract goes through the contract dialog.

## 2026-11-08: One review per loop

The user asked for one reviewer per round, after a raspi-initializer loop
started a second review agent on the fixes for the first one's findings,
because those fixes again touched more than three files (a count the
configuration no longer uses). The two reviews took about half an hour of one
turn. `[Iterate]` step 6 and the working style's decision table now say that a
loop runs at most one review agent, and that the fixes for its findings are
verified by the loop's tests and `[Check]`, not by another agent.

## 2026-11-08: Contract changes on the round's page, and no review gap

The user asked for three changes to the round's page and one to the review.
A review agent on the first version found that the page rule still let other
rules place decisions apart from their items, and that the review gap stayed
open in three cases; the rules below include those fixes.

- **A contract change is a decision on the page.** A proposed change to a
  project's `CLAUDE.md` or `AGENTS.md` was asked in a question dialog, the one
  exception to "consult once per loop". It is now a decision like the others,
  with the exact new text beside each option, and no question goes into a
  dialog, also where a skill asks for one. The 2026-10-31 entry on project
  contracts, and the dialog named in the 2026-11-04 review entry and in the
  2026-11-08 entry on `[Distill]`, are historical now.
  `hooks/contract-dialog.sh` and its two entries in `settings.json` are
  deleted, because the dialog header it counted no longer exists. The limit of
  one dialog per five turns went with it, since it counted dialogs; whether
  the page needs a limit of its own is left to the user. `[Iterate]` no
  longer writes a repeated bug into the contract by itself: it enforces the
  rule and proposes the contract text. The notification on `AskUserQuestion`
  stays, because a skill outside this configuration may still open the dialog.
- **Everything about an item stands in the item.** A change, a finding, an
  outlier or a plan step holds its status, where it was verified, its
  picture, how the request was read and what was decided for it, its test
  steps and the decision it raises. A decision holds its context, its evidence
  and, beside each option, that option's consequence and picture. The first
  version kept every decision in a list at the end, which left an outlier's
  facts in a table and its decision at the bottom, matched by ID. `[Distill]`
  and `[Rethink]` now place each decision in its outlier or finding, and the
  block at the end holds only the decisions that concern no single item.
- **Every statement has a text field and an ID.** Before, only decisions and
  the lines under "Read as" and "Decided for you" had a field. Now every line
  and table row has one, and the copied reply collects them by ID. All IDs on
  a page continue one number sequence through the conversation, so that a
  reply such as "12: still old" cannot mean two items; the user's own
  numbering of a request stays beside its ID as a label.
- **The weekly review reads the page.** `extract_rounds.py` saw only the
  terminal text and the dialog, so contract decisions and replies that point to
  a statement's ID would have been lost to it. It now also takes the text of
  the last HTML page written with the Write tool in each round; a page written
  by a script is not seen, so `[Iterate]` writes the page with the Write tool.
- **What changed after a review is reviewed in a later loop.** The entry "One
  review per loop" above left the fixes for a review's findings to the tests
  and `[Check]`. Now the loop commits what the agent saw before it fixes the
  findings, so that the fixes and whatever the repeated check changes are
  commits of their own. The report names them by commit message, in the state
  line and in the terminal message, and every later report repeats them until
  an agent has seen them. The next loop starts its agent for them even
  without a critical change of its own, and a question answered in between
  does not drop them. A loop still runs one agent. A session that starts
  without that list in its conversation does not know of the commits; whether
  to record them on the machine is left to the user.

## 2026-11-08: Second review of the page rules, and distilled fixes

The review agent of the next loop read the commits made after the first review
(as the entry above asks) and found that the new rules named one thing in
three ways, contradicted each other in places, and that the weekly review read
some pages wrongly. The same loop distilled this configuration; the fixes
below that are naming or consistency corrections were made at once, and its
other outliers went to the user as decisions.

- **One name: "the changes made after a review".** "Changes no review agent
  has seen" also matched every ordinary change that never needed a reviewer,
  so every later loop would have had to start one. The name now means only
  what was committed after a review agent started.
- **`[Split commits]` runs before the agent starts**, not before the fixes.
  Committing "what the agent saw" afterwards would also have committed edits
  made while a background agent ran, as if reviewed. The commits it reviews may
  still hold what it finds; the step says so, and nothing is pushed or shipped
  before the fixes are committed, which keeps "fix an invariant before it
  leaves" true in effect.
- **Every place that repeats the hand-back's ending repeats the list**: rule 1
  and `[Check]`'s forced message, which now points to rule 1 instead of
  restating it. A question round does not repeat it; the next loop still finds
  the changes, because it looks at every earlier loop.
- **The page is written with the Write tool into the scratchpad, its text in the
  markup, and changed only with the Write or Edit tool.** Measured on the
  sessions since 2026-11-01: 31 of 152 pages held most of their text in a
  script, 24 of 115 rounds edited the page after its last Write, 2 rounds wrote
  a project's own HTML file, and 20 of 152 pages were longer than the 6000
  characters kept. The rule moved from `[Iterate]` into the working style, so
  that every skill that writes a page follows it. `extract_rounds.py` now
  applies the round's Edit calls to the page, takes only HTML in a scratchpad,
  and keeps 15000 characters.
- **Smaller corrections.** A prefixed ID sequence (C1, R1) continues through the
  conversation like the numbers; a carried decision brings its item's facts;
  a test step or a plan step's decision stands in its item; the review notice
  names the next `[Iterate]` loop; "the project's contract" replaces
  `CLAUDE.md` where `AGENTS.md` may hold it; `[Iterate]` may start a whole
  review when the user's message asks for one; the design history says
  "user" throughout.
- **The round's page replaced Artifacts on 2026-11-01** (commits 1fc7bc3 and
  0e6586a), without an entry here. The 2026-10-31 sentence that pictures are
  always Artifacts is historical since then.
- **Deleting a hook script may break running sessions.** A session that keeps
  the hook list it started with, but runs each script by path, would report an
  error on every prompt after the script is deleted. The session that deleted
  `contract-dialog.sh` recorded no such error, so Claude Code may reload the
  hook list; this was not settled.

## 2026-11-08: Decisions on the distilled configuration

The user answered the decisions of the distill and of the two rounds before it.

- **Kept as built**: no limit on how often a contract change is proposed;
  decisions inside the item they concern; the list of changes made after a
  review lives only in the conversation; the skills that run on request stay
  startable by a request in plain words.
- **Numbers inside an item.** One number per line made a page reach 86 in two
  rounds. An item now takes the next number and its lines and decisions are
  numbered under it (11.1, 11.2A).
- **The terminal stays short.** The user asked for it. The terminal now gives
  the number of changes made after a review that no agent has seen, and the
  page lists them; a message before the hand-back is one line, and a plan
  stated up front (`CLAUDE.md`, "Define done") one line per step.
- **No "Claude is done" line in the chat.** The `Stop` hook printed it after
  every turn, below the hand-back, against hand-back rule 1. The desktop
  notification and the bell stay.
- **The check gate counts every turn.** It started a turn's count only when the
  user typed. A turn the user interrupted lost its unchecked writes, and a turn
  resumed by a finished background agent kept the previous turn's "settled"
  flag. Now writes that no check has seen stay pending across turns, a checked
  turn ends with a fresh starting point, and a separate `blocked` flag marks
  the one block per turn, so that an interrupted forced check keeps its writes
  pending. Tested with turn patterns in a scratch home. Accepted gaps: a
  background shell command that writes after its turn ended, with no tool call
  marking it; writes made after `[Check]` ran in a turn that is then
  interrupted (as before); and the user's own edits between turns, which count
  when the next turn is resumed rather than typed, or follows a turn with
  pending shell writes, and then cause one extra check.
- **One session per project at a time.** `[Check]` and `[Split commits]` take
  everything uncommitted as the session's own; the user keeps two sessions out
  of one project, and `[Split commits]` states the assumption.
- **The weekly review sees interruptions, rejections and forced checks.**
  `extract_rounds.py` dropped them although `[Review config]` asks for them.
  Over all 1314 rounds on this machine it now counts 351 interruptions, 380
  forced checks and 13 rejected actions, one line per round. An interruption
  that directly follows a rejection is the same event and is not counted
  again.
- **The weekly review runs once, also after /clear.** The notice now also comes
  after /clear and compaction; the pull still runs only at start and resume,
  so that a session working in this repository is not fast-forwarded under it.
  The review writes `config-review-started` when it starts, which keeps the
  notice from sending a second session into another review, and copies that
  time into `config-review-last` once its proposals stand on the page; a review
  that stops earlier leaves its rounds to the next one. A missing, unreadable
  or future stamp counts as never reviewed. The 2026-10-31 sentence on when the
  stamp is written is historical.
- **Every skill hands back the same way.** `[Universalize]` invokes `[Check]`
  before its page and names only failing or skipped tests; `[Split commits]`
  outside a loop reports in one to three lines without hashes;
  `[Review project]` hands back a review page with "Fix all except ...?";
  `[Review config]` commits only the files it changed, one commit per picked
  row, since another session may have its own work open in this repository.
  No skill invoked inside a loop prints a report or writes a page of its own.
- **One place for each rule.** `[Universalize]` points to `Naming`,
  `Universality`, `Comments vs. design history` and `Prose style` in
  `CLAUDE.md` instead of restating them; how to brief a read-only helper agent
  is one row of the working style's decision table; the commit line is defined
  in `[Commit message]` alone; the hook headers say what each script does and
  leave the reasons to this file.
- **The configuration repository is pushed after every loop that commits to
  it**, once the review's fixes are committed. Other machines pull it
  automatically at session start, and a machine that holds unpushed commits
  can no longer fast-forward once another machine has pushed.
  A push refused because another machine pushed first is rebased, checked
  again and pushed; a conflict becomes a decision.
- **From the review of these changes.** The page goes into a folder of its own,
  so that serving it on the network does not expose the session extracts next
  to it. The session reader keeps every page of a session and takes the one the
  hand-back names, so that a round which only edits the last page, or writes a
  mockup after it, still shows the right page. "Fix every finding at once"
  applies to the loop's own review agent and `[Check]`; a whole review the user
  asked for waits for the user's pick.

## 2026-11-08: A test for the check gate

At the user's choice, `hooks/test-check-gate.sh` keeps the turn patterns that
verified the gate's carry-over. It runs the gate in a throwaway home folder
and repository, with the user's git configuration switched off, and exits
non-zero on a wrong verdict. With the carry-over removed from `reset` it
reports four failures, so it detects the regression it exists for. It is the
configuration's first test; `[Check]` runs it when the gate changes, as it
runs any test next to the code it reviews.

## 2026-11-08: Review of the gate test and of the distilled changes

One agent reviewed the gate test together with the commits the previous review
had not seen.

- **An inline check does not settle the gate.** When the `check` skill is not
  registered, the forced review runs inline and makes no Skill call, so the
  writes stay pending and the block comes back after every turn until a
  restart. The case needs a session that started before the skill existed.
  Settling on a Read of the skill file was rejected: reading that file for any
  other reason would then settle the gate without a check. The block message
  now says that the block repeats.
- **The test catches four more regressions**: a skill other than `check`
  settling the gate, `reset` keeping `settled`, a checked turn keeping the old
  starting point, and a folder outside any repository counting as unchanged.
  Each was verified by running the test against a gate changed in that one way.
- **Two more accepted gaps, pinned by the test.** A turn that a finished
  background agent resumes fires no `UserPromptSubmit`. After a turn that ran
  `[Check]` and was then interrupted, the resumed turn's writes pass unchecked,
  because the leftover `settled` flag settles them. After an interrupted forced
  check, the resumed turn ends unblocked and its writes stay pending for the
  next typed turn. Clearing `settled` on a later write was rejected: the
  round's page is written after `[Check]`, so every loop would end with a
  second, forced check after its hand-back.
- **A future review stamp no longer discards the other one.** Each stamp file
  is read on its own, and a value in the future counts as never. Before, a
  future `config-review-last` cancelled a valid `config-review-started` and made
  the review due at every start. The session reader treats a future or
  negative start time as 0 for the same reason. The review counts as finished
  also when it found no proposals, and `[Iterate]` says when its finishing copy
  runs: after the page is written, before the terminal message.
- **The review applies nothing while another session works in the
  configuration repository.** `[Check]` and `[Split commits]` take every
  uncommitted change as their own, and the push would publish the other
  session's commits before their review's fixes. Uncommitted changes or
  unpushed commits that the applying session did not make now leave the picked
  rows unapplied, with the reason on the page. This replaces the sentence of
  "Decisions on the distilled configuration" that the review commits only its
  own files.
- **A refused push.** `[Check]` reviews uncommitted changes only, so after a
  rebase it has nothing to see. The rebase is now followed by the gate test,
  and a conflict aborts the rebase before the push becomes a decision, so that
  the repository does not wait in the middle of a rebase.
- **The pull also runs after /clear.** The reason for skipping /clear, not to
  fast-forward the repository under a running session, holds for compaction
  alone: compaction continues a loop in the middle of its work, while /clear
  starts a new conversation that should read the newest configuration. This
  replaces that sentence of "Decisions on the distilled configuration".
- **Session reader.** The flag that keeps an interruption directly after a
  rejection from counting twice is cleared by the next assistant entry, and a
  rejection and an interruption in one entry count once. When a hand-back names
  several pages, the one written or edited last is shown. Over all rounds on
  this machine the counts are unchanged.
- **Wording.** The consult list's line on review findings names the loop's own
  review agent and `[Check]`, as the decision table does; the review's first
  step no longer calls the due message a "weekend notice".

## 2026-11-12: Subagents only read

The user stated the rule: a subagent is used to review, never to change; every
change is the main session's. Every skill already started its subagents read
only, but no file stated the rule, and a `general-purpose` subagent has every
tool.

- **Where it is stated.** One section, "Subagents", in `working-style.md`, named
  with the user's word. The skills keep calling their agents read only and
  point to the brief there. "Review" is read as reading of every kind (a
  review, a search, reading sessions or web pages), because `[Distill]` and
  `[Review config]` collect with subagents and web pages are read through one.
- **How it is enforced.** `hooks/subagent-read-only.sh` on `PreToolUse`. The
  hook payload carries `agent_id` only for a call from inside a subagent;
  Claude Code documents that field, not `agent_type`, as the way to tell the
  two apart. Inside a subagent the hook refuses the edit tools, the worktree,
  task, schedule and cross-project tools, and every artifact action except a
  read or a listing. A shell command is refused when it matches a writing form:
  a file command (`rm`, `mv`, `cp`, `tee`, `wget`, ...) wherever a command
  starts, also behind `sudo`, `env`, `xargs`, a shell keyword, a path or a
  backslash; a writing `git` subcommand, including `stash`, `tag`, `branch -d`,
  `config` with a value, `worktree`, `remote`, `notes`, `submodule` and
  `fetch`; an in-place `sed` or `perl`; a redirection to a file;
  `find -delete`; a writing `gh` or `curl` call; and a package install. The main
  session's calls exit at the first check, before any parsing, so they cost
  one string match. A call from inside a subagent whose payload cannot be
  parsed is refused, so a missing interpreter does not let the call through.
- **Read-only text that looks like a write passes.** Output to `/dev/null`, a
  duplicated descriptor, an HTML tag such as `<title>`, a comparison with a
  number (`awk '$1 > 5'`), a `gh api graphql` query without `mutation`, and a
  `gh api -X GET` call are taken out before the forms are matched.
- **Accepted gaps.** A shell pattern does not see quoting, so some writes pass
  and some reads are refused. Writes that pass: an interpreter (`python3 -c`),
  a build or a test run (they write output and caches, and a review may need to
  run the tests), a write inside a script file, and MCP tools. Reads that are
  refused: a comparison of two values (`jq '.a > .b'`), a quoted `" > "` or
  `"; rm"`, an HTML tag with attributes, and a search term such as `rm` handed to
  `xargs grep`. The refusal tells the subagent to rewrite the command. Refusing
  the shell inside subagents altogether was rejected: reviews read diffs and
  logs through it, and this build has no separate search tool.
- **The check gate ignores a subagent's `[Check]`.** A subagent's calls carry
  the main session's ID, so a review subagent invoking `check` would have
  settled the main session's gate without the main session checking anything.
- **The built-in `statusline-setup` subagent can no longer edit.** It reports
  the change, and the main session makes it.
- **Tests.** `hooks/test-subagent-read-only.sh` runs writing and reading calls
  from a subagent, a subagent call whose payload cannot be parsed, and calls
  from the main session, including one whose command contains the text
  `"agent_id"`. It reads the matcher from `settings.json` and checks that every
  tool named there is refused, so the two lists cannot drift apart. After a
  refused push is rebased, every hook test runs again, not only the gate test.
  Both tests were run against a hook that refuses nothing and a gate that
  counts a subagent's check, and each reported failures.
