---
name: review-config
description: Review the Claude configuration against the sessions since the last review, and propose exact changes to CLAUDE.md, working-style.md, the skills, the hooks and the project contracts. Proposes only; applies nothing until the user picks.
---

# [Review config]

Runs when the session start reports that the weekly review is due, or when the
user asks for it. It reads how the configuration worked in practice and turns
what went wrong into proposed changes for the loop's Decisions.

## 1. Collect the rounds

The last review's time is in `~/.claude/state/config-review-last` (Unix
seconds); without it, every round counts. Extract them into the scratchpad:

```
python3 -I ~/.claude/skills/review-config/extract_rounds.py "$(cat ~/.claude/state/config-review-last 2>/dev/null || echo 0)" <scratchpad>/rounds
```

One file per project, each round being the hand-back the user saw and the
reply they typed. If nothing came out, write the stamp (step 5) and report
"No sessions since the last review" as the review's single line.

## 2. Read them

Read every round. Above about 300 rounds, split the files among read-only
agents in parallel, one per project or half project, each told to read all of
its file and report evidence with round numbers. Look for:

- **Corrections**: the user said a result was wrong, reverted it, or repeated a
  request that was already "done".
- **Follow-up questions** caused by a hand-back: "what do you mean", "explain",
  "right?", "correct?", "did you do all of it?".
- **Repeated requests**: the same instruction typed three or more times, which
  a rule, a project contract or a skill could carry.
- **Rejected or interrupted actions**, and permission prompts for read-only
  commands.
- **Broken rules**: a hand-back or file that violated `CLAUDE.md` or
  `working-style.md` (the hand-back rules, the prose style, the consult list).
- **Unused or misfiring parts**: a skill never invoked, a hook that blocked for
  nothing, an instruction the sessions kept working around.
- **New preferences** the user stated in passing.

## 3. Compare with the configuration

Read `~/.claude/CLAUDE.md`, `~/.claude/working-style.md`, the skills under
`~/.claude/skills/` (not `synced/`), `~/.claude/hooks/`, `~/.claude/settings.json`,
and the `CLAUDE.md` of every project that had sessions. For each finding,
decide where the change belongs and draft its exact wording, in the prose
style of `CLAUDE.md`. Drop a finding that one occurrence explains and no rule
would have prevented.

## 4. Propose

Proposals join the current loop's Decisions, one entry each:

| ID | File | Change (exact wording, or what is removed) | Evidence (count, two example rounds) | Options |
|---|---|---|---|---|

Options are "apply" and "skip", plus a variant where one is real. The default
if the user does not answer is "skip". IDs start with `C` and stay unique
across rounds (C1, C2, ...).

A change to a project's contract is not a row: it is asked in a contract
dialog, under the rules in `working-style.md`.

## 5. Record the review

Write the time of this review, so that the weekend's other day and the coming
days do not run it again:

```
date +%s > ~/.claude/state/config-review-last
```

## 6. Apply what is picked

In the loop that receives the user's IDs: apply exactly the picked rows, add a
dated entry to `~/.claude/design_history.md` (and to a project's design
history for a project contract), invoke `[Check]`, then commit the
configuration repository in one commit and push it. A project contract is
committed in its own repository and not pushed.
