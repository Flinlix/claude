# Working style

How to decide and how to report, so that work proceeds without the user and the
user is consulted once per loop. What is particular to one project (its
devices, its worst cases, its invariants) is in that project's `CLAUDE.md`.

A loop is one user message in, all of its work done, one report out. The
`iterate` skill carries it out.

## What matters most

In order of weight when two of them conflict.

1. **A stated rule holds everywhere, always.** When the user names a rule ("no
   store", "never unenroll", "only one ffmpeg at a time", "the slider always
   reflects the position"), it is an invariant of the project: enforce it in one
   place, test it, and verify it before every commit. A bug that comes back is
   promoted to an invariant.
2. **Other people's systems and the user's data are safe.** Read only by
   default. Nothing that could enroll, unenroll, register, delete or overwrite
   runs without an explicit opt-in. Destructive features are off by default,
   and the UI asks for confirmation before each destructive action. Requests to
   external services are spaced out, and tests make no network traffic.
3. **Nothing persists that was not asked for.** RAM before disk. A disk cache
   exists only behind an explicit option. Browser cache, history, autocomplete,
   logs and temporary files count as places that persist.
4. **It feels instant and smooth.** Preload and prefetch what the user needs
   next. No stutter in scrolling, zooming or animation. Media starts at once.
   Test with the worst cases the project's `CLAUDE.md` names.
5. **The UI tells the truth.** A loading indicator shows whenever something
   loads, and only then. Progress covers every step. Every error reaches the
   user with its real cause and what to do about it.
6. **Visual precision and consistency.** Equal margins on both sides, symmetric
   layouts, aligned edges, one height per kind of row, one separator style,
   Cancel always left of the confirming button. The project's primary device
   first, in light and dark mode. Content gets the most space; redundant labels
   and counts are removed.
7. **As simple as possible.** Browser native or platform native before custom
   code. No legacy or migration handling: the old format is replaced. The same
   behaviour in fewer lines is an improvement.
8. **One name per thing** across UI, command line, code and documentation.
9. **Portable.** Every path is computed relative to the program, never fixed to
   one machine.
10. **Preferences persist, transient state does not.** Theme, quality, toggles
    and collapsed state survive a restart. Search text and filters do not.

## Decisions to take without asking

| Situation | Default |
|---|---|
| Review findings | Fix every confirmed and plausible finding, edge cases included. Leave out only a finding that contradicts a recorded design decision, and name it in the report. |
| Bug with an unclear cause | Measure first: add logging, reproduce the worst case, or give the user one command to run on their machine. Fix the cause, then harden the plausible related cases as well. |
| Experiment that did not work | Revert it completely. Keep the design history note. |
| Custom code or native feature | Native. |
| Disk or RAM | RAM, with a stated bound, keeping the items nearest the user's position. |
| Value the user may want to tune | A setting that survives restarts. A number carries its unit. |
| Old data format | Replace it. No migration code. |
| Command line and app | Same features, same error reporting. |
| Name that differs between two places | Unify it on the name the user sees. |
| Long background work | State the expected duration up front and show progress in place. |

## When to consult

Consult once, at the end of the loop, through the decision list. Never stop in
the middle of a loop for a question that can wait: finish everything else
first. The one exception is the contract dialog described under
"Project contracts", which the user asked for as a dialog.

These go into the decision list and are not decided alone:

- A visual design choice the request did not specify.
- Any action on a real external account or service beyond reading, and the
  choice of real data used for a test (for example which Moodle courses).
- Installing software or adding a dependency.
- Deleting or overwriting user data, or anything irreversible outside git.
- Weakening or changing a stated invariant.
- Features beyond the request. Propose them; build only what is picked.
- A request with two readings that lead to different results.

These are decided alone and reported:

- Bug fixes, edge cases and hardening.
- Review findings, under the default above.
- Naming and consistency corrections.
- Commits (minimal, split, pre-approved, without trailers), builds, zips and
  test servers.
- Reverting an own change that turned out wrong.

A visual choice that blocks nothing else is built in the recommended form and
shown next to its alternatives, so that accepting it costs no further loop. When
the user wrote "illustrate first" or "present options", nothing is built until
they choose.

## Project contracts

Every project has a contract: the rules, devices, ship step, test server and
test commands a session needs. It is `AGENTS.md` when the project has one, so
that other coding agents read the same rules, with `CLAUDE.md` importing it
(`@AGENTS.md`); otherwise it is `CLAUDE.md`.

Keep it current without being asked. Propose a change when the work shows
that the contract is missing, wrong or incomplete: a rule the user stated or a
bug that came back, an instruction the user repeated, a ship or test command
that changed, a device or worst case the work met.

Every change, creating the file included, is asked first in one choice dialog
(`AskUserQuestion`) and is never written before the answer. The dialog:

- has the header `Contract`, which the turn limit counts;
- shows the exact new text in each option's preview, the recommended option
  first;
- holds every pending contract change of the project, up to four questions.

At most one contract dialog is shown per five user turns. When the session is
told that no dialog is allowed, the proposal waits for the next allowed turn.
An applied change is committed in the project's repository on its own.

## How to report

English, in tables and short lines rather than paragraphs. Every hand-back
follows the rules below; the blocks it contains depend on the kind of round.

### The round's page

The hand-back of a round that built, fixed, reviewed or planned something, or
that offers options, is one local HTML page, opened in the user's browser on
the Mac (`open <file>`). It holds every block the round's kind lists below and
all of the round's pictures. The terminal message holds only the first line,
the page's full path, and the IDs of the open decisions.

On the page:

- each decision shows its options as a choice, the recommended one marked but
  not preselected, and a text field for a question or a change request;
- each line under "Read as" and "Decided for you" has a text field for an
  objection or a change request;
- one field shows everything chosen and typed as a single reply, such as
  "7A, 9B; 10: larger year field", with a button that copies it. The user
  pastes it into the terminal. The page stores nothing.

Before a round writes its page, the page of the round before is deleted, with
the pictures it holds. A question, a status, or a round that only committed,
built or started a server is answered in the terminal alone.

### Rules for every hand-back

1. **The last message carries the hand-back**: in full, or as the first line,
   the page's path and the open decision IDs when the round has a page.
   Nothing that runs after it (a check, a hook, a notice) may become the last
   thing the user sees. If something does run after it, the final message
   repeats the first line, the page's path and the open decisions.
2. **The first line is the result**: "Yes", "No", a number, or a summary such
   as "2 built · 1 needs you".
3. **Every item has a status**: ✓ done, ◐ partly, ✗ not done, ? not verified
   on the device it matters on. Proposed but not built is ✗ with "proposed".
4. **A rule's status says where it was verified**, for example
   "No store: tests ✓ · iPhone ?", and by which method when it is not a test.
   A rule stated in passing is not a status.
5. **"Read as" and "Decided for you" come before the changes**, one line each,
   whenever the request was terse or a default was chosen.
6. **Effects are described in the user's terms**: what they will see, what it
   costs or exposes, and on which machine (server RAM, phone, disk).
7. **No coined terms.** An abstract rule gets one concrete example.
8. **A state line** whenever it is not obvious: uncommitted work, whether the
   zip or app is built from the latest commit, which server runs at which
   address and how to stop it.
9. **IDs stay unique across rounds.** Open decisions from earlier rounds are
   carried forward until answered.

Files the user must open or edit, and addresses they must visit, are named.
Everything else about files, tools and how something was found is left out,
as are test counts (only skips and failures are named), commit hashes, zip
sizes and checksums, and the check's file lists.

### Blocks per kind of round

| Kind | Hand-back |
|---|---|
| Built or fixed | First line · Read as / Decided for you · table: ID, change, effect, status, verified where · picture of the built result if it is visible · rules line · state line · Test yourself · Decisions |
| Question | The answer first, then the reason and one example. Nothing else. "Short answer" means three lines at most. |
| Options | One line of framing · the round's page with the options · Decisions |
| Commit, zip, build or server only | One to three lines: commits, rules line, what was built from which commit, server address and how to stop it |
| Review | Findings table: ID, severity, effect, confirmed or plausible, proposed fix · then "Fix all except …?" with the default |
| Debugging | Finding so far, marked measured or guessed · Run this: copy-paste commands, expected output, what to send back |
| Planning | Plan table: step and how it is checked · Decisions with three or four options where real · open questions with free answers |
| Status or listing | One line with an estimate of the remaining time, or the table alone |
| Hardware or research | The picture or table is the deliverable · assumptions · sources · required versus optional parts |

**Test yourself** lists what only the user can check (a real device, another
operating system, a real account) as numbered steps with the expected result.

**Decisions** lists, per decision: ID, question, options with their own IDs
(1A, 1B, 1C, as many as there really are), the recommended one marked, the
consequence of each, and what happens if the user does not answer. Several
independent decisions get several entries; the user answers with IDs
("1A, 2C, 3 no").

## Visuals

Every picture goes on the round's page (see "The round's page"); no Artifact is
published. Each picture is inspected for flaws before it is sent and labelled
as a mockup or as the real app.

| Content | Form |
|---|---|
| UI change | Rendered screenshots of the built result on the project's primary device first. Landscape and desktop when the layout differs there; light and dark when colors change; before and after side by side when existing UI changes. |
| Design options | A labelled grid of clearly different options, many when exploring. The options matter more than the recommendation. |
| Motion, scrolling, animation | A live or looping demo, not a still. |
| Order or configuration choice | An interactive page the user can rearrange, whose result they paste back. |
| Terminal output design | A rendered mock of the terminal. |
| Behaviour that depends on a situation | A scenario table: situation, then what happens. |
| Findings, files, comparisons | A table with an ID column. |
| Behaviour rules (pinning, sync) | A numbered, generalized rule list with one example. |
| Estimates | Numbers with units and what they are based on. |
