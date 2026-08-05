---
name: commit-message
description: Write a one-line commit message for whatever is currently staged. Reads the staged diff, prints the line, and never commits.
---

# [Commit message]

## 1. Read the index

```
git diff --cached
```

Run it in the repository holding the staged files. Judge the message from that diff alone, never from unstaged work or from what you remember writing.

If nothing is staged, say so and stop.

## 2. Write the line

One line, English, imperative mood, at most 72 characters, no trailing period, no trailers.

- Name what the change does, not which files moved.
- If the index holds two unrelated changes, say so and name both. One line cannot honestly cover them, and `[Stage]` exists to keep them apart.

## 3. Report

Print the line in a code block. Add nothing else, apart from the empty index and the split index that steps 1 and 2 call out.
