---
name: iterate
description: The standing development loop. Deliver every request in the user's message without stopping, verify the project's invariants, commit, ship, and hand back one report that batches every decision the user has to make.
---

# [Iterate]

One pass is one loop: the user's message in, one report out. The user is
consulted once per loop, at the end. `~/.claude/working-style.md` says what to
decide alone, what goes to the user, and how the report reads. Follow it.

## 0. Load the project's contract

Read the project's `CLAUDE.md`. It names:

- **Invariants**: the rules that must hold, and how each is verified.
- **Ship**: what to build after the loop's commits (a zip, an app), and how.
- **Test server**: how to run the project for the user's devices, and how to stop it.
- **Tests**: the commands that run the tests, linters and type checks.
- **Devices**: where the user runs the project, and its primary device.

If the file is missing or lacks one of these, derive the content from
`design_history.md` and the user's earlier messages and use it for this loop.
Propose the file or the missing part only when the work showed a rule worth
writing down, as a decision on the round's page, as `working-style.md`
describes under "Project contracts". The project's contract
may be `AGENTS.md`, imported from `CLAUDE.md`.

## 1. Plan new work first

New work, such as a new project or a feature with open design questions, has no
plan to build against yet. Then this loop produces the plan instead of code:
goal, stack, scope, invariants, the steps through to done, and a design
illustration for each step that has a visible result. Every open point becomes
a decision with options. Build nothing whose shape depends on an open point.

Once the user has answered and nothing material is open, the plan stands. From
then on every loop builds everything the plan settles at once, not one step per
loop. Only what is still uncertain goes back to the decision list.

Record the plan as a dated entry in the project's `design_history.md`, so that
a later session builds against the same plan.

## 2. Split the message into items

Give every request an ID, under rule 9 of the hand-back rules in
`working-style.md`. The user's own numbering stays beside it as a label.
Sort each item into exactly one class:

- **Do**: everything `working-style.md` lets you decide alone.
- **Decide**: an item on its consult list. Prepare it in step 4.
- **Answer**: a question. Answer it in the report, in the form the working style
  prescribes.

Answers to the previous loop's decision list are items too.

## 3. Do

For each item, state done as something checkable first: a test that reproduces
the bug, a test that tries to violate the invariant, a render that shows the
layout. Then build until it passes.

- A UI change is rendered at the sizes the working style lists, and every
  render is inspected for flaws before it is shown.
- A repeated bug becomes an invariant: enforce it in one place now, and
  propose it for the project's contract as a decision.
- Do not stop for a question that can wait. Record it for the decision list and
  carry on with the rest.

## 4. Prepare the decisions

For each **Decide** item, write the options with lettered IDs, the recommended
one first, and one line on each trade-off. Render visual options onto the
round's page, each beside its option.

When the working style allows it, build the recommended option now, so that
accepting it costs no further loop. Never do so for an item the user asked to
see first, or for anything that touches a real external account, installs
software or deletes data.

## 5. Verify

- Run the tests, linters and type checks, and record the real result. A skipped
  test verifies nothing: name it in the report as not run.
- Invoke `[Check]` on the loop's changes.
- Verify each invariant in the project's `CLAUDE.md` by the method it names.
  Where it names none, read the loop's changes against it, and say in the
  report that this was the method. An invariant that does not hold is fixed
  before anything is committed.

## 6. Review a critical change

When the loop made a critical change, or an earlier loop left changes that no
review agent has seen, start one fresh agent, read only, on both and the code
they touch. A change is critical when it touches:

- a rule in the project's contract, or the code that enforces one;
- anything that deletes, overwrites or erases data, or writes to another
  system;
- credentials, permissions, or what is reachable over a network.

Give the agent the diff, the project's contract and the instruction to change
nothing, and none of your own conclusions. Ask for findings with file and line
evidence. Confirm each one, fix them under the default in the working style,
then repeat step 5. A finding left out goes into the report with its reason.

One review per loop. Before fixing its findings, invoke `[Split commits]` on
what the agent saw, so that everything changed after the review (the fixes,
and what the repeated step 5 changes) forms commits of its own. Step 5
verifies them; the report names them by commit message as not reviewed yet,
and every later report names them again until an agent has seen them. A
session that starts without that list in its conversation does not know of
them.

Never invoke `[Review project]` or `[Rethink]` here, and never offer them in
the report; they run only when the user asks.

## 7. Commit and ship

- Invoke `[Split commits]`. The user has approved the commits in advance.
- Run the project's ship step once, after the loop's last commit, in every loop that committed a
  change to what it builds, however small. A hand-back never reports a commit as not built yet.
- Start the test server if the loop changed something the user tests on a
  device. Leave it running and say where.

## 8. Report

If the session start reported that the weekly configuration review is due,
invoke `[Review config]` first; its proposals join this report's Decisions.

Write the report exactly as `working-style.md` prescribes: the round's page,
each decision in the item it concerns, opened in the browser, and in the terminal
the first line, the page's path or address, the open decision IDs and the
changes no review agent has seen yet. It is the last message of the turn:
nothing that could produce another message, `[Check]` included, runs after
it. The skills and the agent this loop invoked (`[Check]`, the review
agent, `[Split commits]`) do not print reports of their own while it runs; their
results go into this one. Then stop. The next message starts the next loop.

Stop the loop early only when a **Decide** item blocks every remaining item.
Report what was done up to that point in the same format.
