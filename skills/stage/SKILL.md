---
name: stage
description: Stage one complete but minimal, commit-sized slice of the current changes, then report a short German summary and an English one-line commit message. Stages only, never commits.
---

# [Stage]

Pick **one** coherent slice of the working tree, stage it, and hand back the text needed to commit it. Staging only, never run `git commit`.

## 1. Locate the repository

The working directory is not necessarily the repository root, and a workspace may hold several independent repositories side by side. Resolve the repository that actually contains the changed files:

```
git -C <dir-of-changed-file> rev-parse --show-toplevel
```

If the changes span more than one repository, stage in one of them and name the others as remaining work.

## 2. Survey

`git status --short` and `git diff`. If something is already staged, review it and fold it into the candidate slice or unstage it. Never leave an unreviewed leftover in the index.

## 3. Choose the slice

- **Complete.** It stands on its own: no half-finished rename, no call site pointing at a function that is now gone. Normally that also means it imports, it builds, and the tests touching it still pass. A skeleton increment is the exception: bodies deliberately left empty with a `// TODO` may leave the tree not building, and are staged anyway. What the rule preserves either way is that nothing is *accidentally* broken. A marked gap is not breakage; a call site left dangling by a rename is.
- **Minimal.** One logical change. A feature plus an unrelated typo fix is two slices, not one.

With several independent changes present, take the one the others build on first.

## 4. Stage

`git add` the chosen paths explicitly. Never `git add -A` or `git add .`, because they sweep in the slices you just decided to leave out.

If one file contains two slices, stage the whole file only when splitting it would leave either half broken. Otherwise say so and leave the split to the user.

## 5. Report

```
── Staged ─────────────
<paths>

── Änderungen ─────────
<2–4 Sätze auf Deutsch: was sich geändert hat und warum. Wenn der Slice nicht baut, steht das hier.>

── Commit message ─────
<one line, English, imperative mood, ≤72 chars, no trailing period>

── Nicht gestaged ─────
<verbleibende Slices, oder "nichts">
```

No `Co-Authored-By` trailer.

Then stop. Running the commit is the user's call.
