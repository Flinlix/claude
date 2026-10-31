---
name: check
description: Review the changes just made, in code and in documentation, for errors, flaws, and inconsistencies, then fix them. Runs after every change, before committing.
---

# [Check]

Verify what was just written, then fix it. Review **the current changes** and the code they touch, not the whole repository, and fix everything that review turns up.

## 1. Scope

Establish exactly what changed: `git status --short` and `git diff` (plus `git diff --cached`) in the repository enclosing the changed files. Outside a repository, use the files touched in this session. The gate asks after every turn that could have written, so a turn that changed nothing is expected: stop there, without a report.

## 2. Inspect

Read each changed file in full. Read adjacent connected files as well. A diff hides breakage in the code around it.

**Correctness**
- Does it do what the change was meant to do?
- Off-by-one, inverted condition, wrong operator, wrong variable
- Unhandled error paths, missing `None`/null cases, leaked file handles or sockets
- Call sites, imports, and signatures that no longer agree after a rename or move

**Stale and unused**
- Symbols imported but unused; symbols used but no longer defined
- Branches, helpers, or code paths the change made unreachable but left in place
- Comments, TODOs, or flags referring to something the change removed or replaced

**Invariants**
- Which rule must hold across this code, and can any path the change opened break it?
- A new call site that bypasses the boundary where the invariant is enforced
- An invariant the change silently redefined, with the old checks or docs left behind

**Consistency between code and documentation**
- Docstrings, README, and design notes still describing the old behaviour
- Documented defaults, flags, paths, and env vars that no longer match the code
- Examples in the docs that would now fail if someone ran them

**Quality** (the rules in `~/.claude/CLAUDE.md`)
- Duplicated logic that belongs in one place
- A function doing more than one thing
- Vague names; comments that restate the code instead of explaining how it works
- A non-obvious decision that never made it into `design_history.md`

## 3. Verify by running

If the affected area has tests, a linter, or a type checker, run them. Report the real result. Never claim a check passed that you did not execute. If nothing is runnable, say that instead.

## 4. Fix, then report

Fix everything you find. A flaw inside the change, a flaw in code the change never touched, and anything you are less than certain about are all repaired here, never deferred. Say which fixes you were unsure about so the user can review the decision.

Name the fixes outside the change separately. `[Split commits]` gives them a commit of their own, so each commit stays minimal and no known defect stays in the tree.

`Open` is for what you could not repair: a fix needing a decision from the user, which also goes on the decision list, or one a missing permission or tool blocks.

When `[Check]` runs inside an `[Iterate]` loop, its result goes into the loop's report and it prints nothing itself. Otherwise the report is one line at the end of the reply, never at its start:

```
Checked: <what ran and its actual result>. Fixed: <short list, or "nothing">.
```

Add `Outside: <fixes in code the change never touched>` and `Open: <what you could not fix, and why>` to that line only when they are not empty. A turn that changed nothing gets no report at all.

When the gate forces `[Check]` after the turn's hand-back was already written, the check's message becomes the last one the user sees. End it by repeating the hand-back's first line and its open decisions.
