---
name: process
description: The standing development workflow. Interrogate the requirements and agree a complete plan, then deliver it one minimal increment at a time, each increment checked, staged, and handed back to the user before the next begins.
---

# [Process]

One pass through this skill delivers **one** increment. Never chain two increments without the user in between.

## 0. Interrogate, then plan

Before writing any code, use `AskUserQuestion` repeatedly until nothing material is still open. Ask about anything whose answer would change the design:

- What is the actual goal, and how will we know it is reached?
- What is explicitly out of scope?
- Which existing code should this reuse, extend, or replace?
- Inputs, outputs, formats, error behaviour, edge cases
- What must always hold: the invariants the code may never violate, and what breaks if one does
- Constraints: performance, hardware, dependencies, compatibility
- Where do new files belong?

One question too many beats one guess. If an answer opens a new question, ask that one too. Only stop when the remaining unknowns genuinely would not change what you build.

Then write the **complete** plan (every increment through to done, not only the first) and get it approved. Use plan mode (`EnterPlanMode` / `ExitPlanMode`) so it is reviewed before anything is written.

## 1. Build one increment

Exactly one of:

- **Something new** → the minimal MVP that works end to end but really consists of the bare minimum and does only implement a part of the plan. No configuration knobs, no abstraction layers, no features nobody asked for yet.
- **Something existing** → one small, self-contained addition.

Follow the quality rules in `~/.claude/CLAUDE.md`. Build the increment and nothing past it.

An increment ends with its invariants enforced, not pending. The validation guarding what *this* increment introduces belongs in it, not in the next one. That is not building past the increment; it is finishing it.

## 2. [Check]

Invoke the `check` skill on what you just wrote, and fix what it surfaces.

## 3. [Stage]

Invoke the `stage` skill. Report its German summary and English commit message.

## 4. Hand back

```
Increment <n>/<total>: <what was built>
Checked:  <result>
Staged:   <paths>
Next:     <the next increment from the plan>
```

Then stop and wait. Do not begin the next increment unprompted.

## 5. Continue

- Increments left in the plan → return to step 1.
- Plan finished → start [Process] again at step 0 for the next piece of work.
