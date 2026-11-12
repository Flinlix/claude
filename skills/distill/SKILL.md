---
name: distill
description: Extract every rule and edge case a project is built on, generalize them into a few principles and kinds of trouble, and name every outlier with ways to fix it. Use when the user asks to condense, generalize or compare the idea of a project, or to find what does not fit it. Proposes only; changes nothing.
---

# [Distill]

The question the user asks as "extract and generalize the rules and edge cases,
present the condensed vision, and name what falls out of it". `[Rethink]` asks
whether the structure should exist; `[Review project]` looks for defects. This
asks what the project stands for, and where it does not live up to it.

## 1. Collect

Read the project's contract (`CLAUDE.md` or `AGENTS.md`), its design history,
its README and the decisions the user recorded. Then start three fresh
subagents in one message, each briefed as `working-style.md` says:

- **Stated rules**: every rule the contract, the design history and the README
  state, with its source, where the code enforces it, and the test that tries
  to break it (or "not tested").
- **Rules only in the code**: behaviour every path keeps although no document
  states it (a check repeated in each step, a refusal, an order that never
  changes), with file and line.
- **Edge cases**: every unusual situation the code or the tests handle, and the
  ones it does not handle, each with what happens and the rule it belongs to.

Merge the three lists. Give rules IDs R1, R2, ... and edge cases E1, E2, ...;
confirm each against the code yourself and drop what does not hold.

## 2. Generalize

- **Principles**: group the rules into five to nine principles. Each principle
  is one sentence a user would understand, one concrete example, and the list
  of rules it covers. Every rule belongs to exactly one principle; a rule that
  fits none is an outlier (step 3), not a new principle of its own.
- **Kinds of trouble**: group the edge cases by the condition that causes them
  (visible before a change, a missing part, a failed change, a lost
  connection, an interruption, a change made by hand, an identity conflict, or
  whatever the project has). Each kind gets one way it is handled, with the
  principles it follows and two or three examples.
- **The vision**: one sentence that the principles spell out.

## 3. Name the outliers

An outlier is a rule, a behaviour or an edge case that breaks one principle.
For each one, check the code before naming it, and sort it:

- **Real outlier**: name the principle it breaks, what happens today in the
  user's terms, and a fix with its size. It becomes a decision with the fix
  and "leave it" as options, the better one recommended.
- **Only looked like one**: the principle was worded too narrowly. Reword the
  principle so it covers the case, and say so.
- **Accepted by a recorded decision**: list it with the decision's ID; never
  propose to reopen it unmarked.

## 4. Report

The round's page, under `working-style.md`: the vision sentence first, then
the principles table (ID, principle, meaning with example, rules covered), the
kinds of trouble (ID, when, how handled, examples), the outliers (ID, principle
broken, today, fix, how it was checked, and for a real outlier its decision),
and the two short lists of apparent and accepted exceptions. Writing the
principles into the project's contract is a contract change: propose it as one
of the decisions, never write it unasked.
