---
name: check
description: Review the changes just made, in code and in documentation, for errors, flaws, and inconsistencies, then fix them. Runs after every change, before staging.
---

# [Check]

Verify what was just written, then fix it. Review **the current changes** and the code they touch, not the whole repository, and fix everything that review turns up.

## 1. Scope

Establish exactly what changed: `git status --short` and `git diff` (plus `git diff --cached`) in the repository enclosing the changed files. If nothing changed, check everything in the current repository. Outside a repository, use the files touched in this session.

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

Fix everything you find. A flaw inside the change, a flaw in code the change never touched, and anything you are less than certain about are all repaired here, never deferred. Say which fixes you were unsure about so the user can review the call.

A body deliberately left empty with a `// TODO` is the agreed content of a skeleton increment, not a flaw. Leave it unimplemented. What you check is that it is marked, that its signature agrees with its call sites, and that nothing around it reads as finished when it is not.

Report the fixes outside the change on their own line. `[Stage]` leaves them out of the increment's slice, so the commit stays minimal and no known defect stays in the tree. This is the sanctioned exception to "Scope of a change" in `~/.claude/CLAUDE.md`, whose ban covers only what gets fixed *uninvited*.

`Open` is for what you could not repair: a fix needing a decision from the user, or one a missing permission or tool blocks.

```
[Check]
Reviewed: <files>
Ran:      <tests/linters and their actual result, or "nothing runnable">
Fixed:    <one line per fix inside the change>
Outside:  <one line per fix in code the change never touched, or "nothing">
Open:     <what you could not fix, and why, or "nothing">
```

If nothing was wrong, one line saying so is the whole report.
