---
name: review-project
description: Review a whole project with fresh, independent subagents, each with its own focus, and return one table of verified findings with IDs and proposed fixes. Runs only when the user asks. Changes nothing.
---

# [Review project]

The review the user asks for as "check the whole project with a fresh agent".
`[Check]` reviews one change; this reviews the whole tree with readers who have
not seen the work.

## 1. Choose the foci

Pick foci for the project. Always include:

- **Correctness**: bugs, edge cases, worst-case inputs and slow I/O.
- **Invariants**: every rule in the project's contract, actively attacked.
- **Consistency**: code against documentation, the command line against the
  app, one name per thing.

Add the foci the project calls for, such as performance and stalls, UI against
the working style's visual rules, safety towards an external service, or
places where data persists.

## 2. Run the reviewers

One subagent per focus, started in parallel, each briefed as
`working-style.md` says.

Nothing in this step may write to an external service. A check against a real
account needs the user's approval of the selection first, through the decision
list.

## 3. Verify

Confirm each finding against the code yourself. Mark it **confirmed** or
**plausible**, and drop what does not hold.

## 4. Report

The round's page, as a review round under `working-style.md`: each finding
with its ID, severity (high, medium or low; most severe first), verdict, what
the user would notice and the proposed fix, then "Fix all except ...?" with the
default. A finding that contradicts a recorded design decision is marked as
such. This skill fixes nothing; the next loop fixes what the user picks.
