---
name: rethink
description: Question the whole structure of a project with several fresh read-only agents: whether each part makes sense at all, and what to restructure, merge, split or remove. Runs only when the user asks. Proposes only; changes nothing.
---

# [Rethink]

The question the user asks as "considering the whole structure, with multiple
fresh agents: anything to completely restructure or rethink? Merge, split or
remove anything? Does it even make sense? Ask that for everything."
`[Review project]` looks for defects in the tree as it is; this asks whether
the tree should be shaped this way at all.

## 1. Choose the project and the foci

The project is the one the user names, or else the one the session works on.
Read its contract (`CLAUDE.md` or `AGENTS.md`), its design history, and the
decisions the user recorded there or in the session, so that no proposal
reopens a recorded decision unmarked.

Pick four to six foci that together cover every part of the project, for
example:

- **Modules**: does each one make sense, have one job, and sit on a boundary
  where two sides change independently? Merge, split or remove?
- **Public surface**: is every entry point used, and is there one way to do
  each thing? What does a real consumer work around?
- **The core approach**: is it the simplest one that keeps the project's rules?
  Is there a fundamentally different design, and what would it cost?
- **State and engine layers**: layering, ownership, concurrency, what exists for
  a case that cannot happen.
- **Tests and documentation as a structure**: does each rule have a test that
  tries to break it? Does the documentation serve the reader?

## 2. Run the agents

One fresh agent per focus, all started in one message, read only. Each gets the
project path, its focus, the project's purpose and rules, the main consumer if
there is one, and the instruction to change nothing. Give no agent your own
conclusions. Ask each for at most 12 findings with file and line evidence, a
concrete proposal, its cost, its effect on the rules, its confidence, and an
explicit list of what is sound as it is.

## 3. Verify

Check every high finding against the code yourself, by reading or by a small
script in the scratchpad. Mark each finding confirmed or plausible, drop what
does not hold, and merge the findings several agents made into one.

## 4. Report

The round's page, under `working-style.md`, with these blocks:

1. **Does it make sense**: the answer in a few lines, first.
2. **Bugs** and **rules that do not hold today**: ID, severity, what the user
   would notice, verdict, proposed fix.
3. **Restructure**, **merge or remove**, **tests and documentation**: ID,
   change, cost, effect on the rules.
4. **Sound as it is**.
5. **Decisions**: one per group, the recommended option marked: the better one,
   however large the change. A proposal that reopens a recorded decision is
   marked with the decision it changes; it is recommended when it is better.
