---
name: process
description: The standing development workflow. Interrogate the requirements and agree a complete plan, then deliver it one increment at a time, each increment scoped with the user, checked, staged, and handed back before the next begins.
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

## 1. Scope this increment

The plan says which piece comes next. It does not say exactly what goes inside this one increment, and that is the user's call, not yours.

Settle it with `AskUserQuestion` before writing anything:

- Which piece of the plan is this increment, and where exactly does it stop?
- Within that piece, what has to work now, and what may stay a `// TODO`?
- Anything the plan left open that building this would force you to decide?

The increment is scoped by the user's answers, not by the original request alone. Keep asking until what you are about to build is unambiguous. If an answer changes the plan, update the plan and say so.

## 2. Build it

Exactly one of:

- **Something new** → the skeleton of the piece agreed in step 1. Signatures, types and call structure in place; bodies may be left empty with a `// TODO`. It does not have to run, and it does not have to build. What it must do is show the shape the finished piece will have, with every gap marked, so nothing reads as finished when it is not. No configuration knobs, no abstraction layers, no features nobody asked for yet.
- **Something existing** → one small, self-contained addition.

Follow the quality rules in `~/.claude/CLAUDE.md`. Build the increment and nothing past it.

Whatever the increment does implement ends with its invariants enforced, not pending. The validation guarding behaviour *this* increment introduces belongs in it, not in the next one. That is not building past the increment; it is finishing it. A body still marked `// TODO` implements nothing, so it carries no invariant to enforce yet.

## 3. [Check]

Invoke the `check` skill on what you just wrote. It repairs everything it finds, so review its report before moving on.

## 4. [Stage]

Invoke the `stage` skill. Report its German summary and English commit message.

## 5. Hand back

```
Increment <n>/<total>: <what was built>
Checked:  <result>
Staged:   <paths>
TODO:     <bodies left empty in this increment, or "nothing">
Next:     <the piece you propose for the next increment, to be settled in step 1>
```

Then stop and wait. Do not begin the next increment unprompted.

## 6. Continue

- Increments left in the plan → return to step 1.
- Plan finished → start [Process] again at step 0 for the next piece of work.
