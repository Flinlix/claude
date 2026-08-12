---
name: split-commits
description: Split all uncommitted changes into a sequence of minimal commits and commit them, each with a one-line message. Plans the whole split, gets it approved, then commits it.
---

# [Split commits]

Partition **everything** uncommitted into an ordered sequence of slices, get the sequence approved, then commit it. Unlike `[Stage]`, this skill does run `git commit`, once per slice.

Reviewing the changes is not this skill's job. Run `[Check]` first if that has not happened. Here the only question is where the seams go.

## 1. Locate the repository

The working directory is not necessarily the repository root, and a workspace may hold several independent repositories side by side. Resolve the repository that actually contains the changed files:

```
git -C <dir-of-changed-file> rev-parse --show-toplevel
```

If the changes span more than one repository, plan and commit in one of them and name the others as remaining work.

## 2. Survey

```
git status --short
git diff
git diff --cached
```

Read every change, tracked and untracked alike. You cannot draw a seam through code you have not read.

If the working tree is clean and nothing is staged, say so and stop. There is nothing to split.

If something is already staged, review it against the rules in step 3. A slice that satisfies them stays in the index and becomes commit 1. Anything else is unstaged, so the plan alone controls the seams. Never leave an unreviewed leftover in the index.

## 3. Partition

**Every uncommitted change belongs to exactly one slice.** Nothing is committed twice, nothing is silently dropped, and the only files still uncommitted at the end are the ones this step deliberately holds back. Step 6 checks that.

Each slice obeys the two rules from `[Stage]` step 3:

- **Complete.** It stands on its own: no half-finished rename, no call site pointing at a function that is now gone. A body deliberately left empty with a `// TODO` is agreed content, not breakage.
- **Minimal.** One logical change. A feature plus an unrelated typo fix is two slices, not one.

Then order them. Dependencies come first: if slice B would not build without slice A, A is committed before B. Documentation describing new behaviour follows the behaviour.

**One file, two slices.** Split it only when neither half is left broken. Otherwise the whole file goes into a single slice, and you say in the plan which other change rode along.

**Untracked files.** They are uncommitted changes, so by default they join a slice. Hold one back instead when it looks like any of these:

- Credentials or key material: `.env` and its variants, tokens, certificates, private keys
- Scratch work: throwaway scripts, notes, sample output, anything under a temp or scratch directory
- Build output, caches, coverage reports, or dependency directories
- Editor and OS clutter, large binaries, anything that belongs in `.gitignore` instead

When in doubt, hold it back. Adding a file to a later commit costs nothing; removing one from published history costs a great deal.

## 4. Present the plan

One line per slice, English, imperative mood, at most 72 characters, no trailing period, no trailers. Name what the change does, not which files moved. If a slice needs two lines to describe honestly, it is two slices.

```
── Planned commits ────
1. <paths>
   <commit message>
2. <paths>
   <commit message>

── Held back ──────────
<file: why it is not being committed, or "nothing">

── Not covered ────────
<other repositories, or "nothing">
```

Then stop and wait. Nothing is committed until the user approves the sequence.

## 5. Commit the sequence

For each slice, in order:

1. `git add` the slice's paths explicitly. Never `git add -A`, `git add .`, or `git commit -a`. Each of them sweeps in the slices you decided to leave for later.
2. `git diff --cached --stat` to confirm the index holds this slice and nothing else.
3. `git commit -m "<the approved line>"`. No trailers, and no `Co-Authored-By`.

Stop at the first failure and report where the sequence broke off. A rejected commit or an index that disagrees with the plan means the later slices are now planned against a tree that no longer exists.

If a hook rewrote files during a commit that succeeded, the tree moved under the plan. Re-survey, adjust the remaining slices, and say what changed before carrying on.

## 6. Report

```
── Committed ──────────
1. <sha> <commit message>
2. <sha> <commit message>

── Working tree ───────
<git status --short, or "clean">

── Open ───────────────
<held-back files, other repositories, slices not reached, or "nothing">
```

The working tree at the end holds exactly what step 3 held back. If anything else is still uncommitted, the partition missed it. Say so plainly rather than quietly leaving it behind.
