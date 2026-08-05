# Design history

Why the configuration in this repository is shaped the way it is. Code comments
explain how something works; this file records why it was chosen, and what was
rejected on the way.

## 2026-08-05: The check gate settles when `check` is invoked, not when it finishes

`hooks/check-gate.sh` blocks the `Stop` event when a turn modified files without
running the `check` skill. Two flag files per session resolve it,
`check-pending-<id>` and `check-settled-<id>`.

**Why a settled flag exists at all.** `check` repairs what it finds, so it edits
files itself, and those edits raise `check-pending` again. With only the pending
flag the same turn would block forever: block, `check` runs, `check` edits,
block again. `settled` records that the gate is resolved for this turn, whether
it was resolved by blocking once or by `check` having run.

**Why `settled` is raised on invocation.** `PostToolUse` on the `Skill` tool is
the earliest signal that `check` was entered, and for a skill that runs inline
in the main loop, no hook event marks the point where it finished. The
consequence is accepted rather than overlooked: a turn that invokes `check` and
then abandons it settles the gate all the same. The gate enforces that `check`
is entered, not that it is carried through. Enforcing the latter would need an
end-of-skill event that does not exist.

Alternatives rejected:

- Have the `check` skill write the settled flag itself. A skill is a prompt, not
  a program, so nothing guarantees the write happens. The hook is the only
  mechanism the model cannot quietly skip.
- Decide at `Stop` time by reading the transcript the payload points at, looking
  for a `check` invocation since the last user message. The information is
  there, but it costs locating the turn boundary and parsing the transcript
  format, and it breaks whenever either changes. A flag the hook writes itself
  carries the same fact without reading anything.
- Let the gate block once per turn and leave it at that, which is what the
  repository actually did until today. Every turn that edited a file was then
  blocked once even when `check` had already run, spending a turn on a review
  that had already happened.

**Correction.** Commit 57bac70 added the `satisfied` mode to the script and
described it in the script header, but never registered the matching hook in
`settings.json`. The mode was unreachable, and the header documented behaviour
the configuration did not implement. Commit 2d286e4 registers `PostToolUse` on
the `Skill` tool, which makes the header accurate.

**Why the payload is inspected rather than trusted.** The `Skill` matcher fires
for every skill, so `satisfied` confirms `"skill": "check"` in the payload
before settling. Without that guard, invoking any skill at all would clear the
gate.
