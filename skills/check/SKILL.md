---
name: check
description: Review the changes just made for errors, flaws, and inconsistencies — in code and in documentation — and fix them. Runs after every change, before staging.
---

# [Check]

Verify what was just written, then fix it. The scope is **the current changes**, not the whole repository.

## 1. Scope

Establish exactly what changed: `git status --short` and `git diff` (plus `git diff --cached`) in the repository enclosing the changed files. Outside a repository, use the files touched in this session.

## 2. Inspect

Read each changed file in full. Read adjacent connected files as well. A diff hides breakage in the code around it.

**Correctness**
- Does it do what the change was meant to do?
- Off-by-one, inverted condition, wrong operator, wrong variable
- Unhandled error paths, missing `None`/null cases, leaked file handles or sockets
- Call sites, imports, and signatures that no longer agree after a rename or move
- Symbols imported but unused; symbols used but no longer defined

**Invariants**
- Which rule must hold across this code, and can any path the change opened break it?
- A new call site that bypasses the boundary where the invariant is enforced
- An invariant the change silently redefined, with the old checks or docs left behind

**Consistency between code and documentation**
- Docstrings, README, and design notes still describing the old behaviour
- Documented defaults, flags, paths, and env vars that no longer match the code
- Examples in the docs that would now fail if someone ran them

**Quality** — the rules in `~/.claude/CLAUDE.md`
- Duplicated logic that belongs in one place
- A function doing more than one thing
- Vague names; comments that restate the code instead of explaining how it works
- A non-obvious decision that never made it into `design_history.md`

## 3. Verify by running

If the affected area has tests, a linter, or a type checker, run them. Report the real result — never claim a check passed that you did not execute. If nothing is runnable, say that instead.

## 4. Fix, then report

Fix what you found **inside the scope of the change**. A flaw in code the change never touched is reported, not fixed — "Scope of a change" in `~/.claude/CLAUDE.md` governs here, and a Check that sprawls into adjacent code defeats the minimal slice `[Stage]` is about to build. Anything you are not certain is wrong is also listed rather than silently changed.

```
[Check]
Reviewed: <files>
Ran:      <tests/linters and their actual result, or "nothing runnable">
Fixed:    <one line per fix, all within scope>
Open:     <out-of-scope findings and uncertain calls, or "nothing">
```

If nothing was wrong, one line saying so is the whole report.
