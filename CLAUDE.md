# Code & Documentation Quality

Apply to every change, in code and in docs. These rules bias toward caution over speed; on trivial work, use judgment.

## Before changing anything

- State your assumptions explicitly. If you are uncertain, ask.
- If the request has more than one reasonable reading, present them instead of silently picking one.
- If a simpler approach exists, say so. Push back where it is warranted.
- If something is unclear, stop and name what is confusing rather than guessing.

`/process` step 0 is the thorough version of this. This is the floor that applies without it.

## Define done before starting

Restate the task as something checkable:

- "Add validation" → write tests for the invalid inputs, then make them pass
- "Fix the bug" → write a test that reproduces it, then make it pass
- "Refactor X" → tests pass before and after
- "Make sure X can never happen" → state X as an invariant, then a test that tries to violate it

For multi-step work, state the plan up front as step → verification pairs. Criteria this concrete let you work independently; "make it work" does not.

## Invariant-driven

Where a change has a rule that must always hold, make the rule explicit and enforce it in one place. Prefer this wherever the problem admits it; not every change has an invariant worth naming.

- **Name them first.** Before writing the code, say what must be true of every input, every output, and the state in between.
- **Structure over vigilance.** A type, a constructor, or a single validated entry point that makes the illegal state unrepresentable beats a check repeated at each use site.
- **Enforce at the boundary.** Validate once on the way in; inside, rely on the invariant instead of re-checking it.
- **Assert what you cannot make structural**, the case that "cannot happen" but would corrupt state if it did. This is not the impossible-scenario error handling ruled out below: an assert documents the invariant and fails fast, it does not handle.
- **Test the property, not three examples.** "Every valid input round-trips" is a stronger check than three inputs that happen to.
- **An optimisation that weakens an invariant is refused.** Record what it would have bought, so nobody rediscovers the trade.
- **When an invariant changes, the old one is dead.** Remove the checks that enforced it and update whatever documented it.

Record *why* an invariant holds, and what it rules out, in `design_history.md`, not in a comment at each site.

## Modularity

A boundary is worth having where two sides can change independently. Draw it
there, and nowhere else: "As simple as possible" still governs, and a boundary
around something that has exactly one implementation and always will is
machinery for a problem that does not exist.

Where you do draw one:

- **A boundary is a protocol, not a base class.** State what a caller may rely on as a structural type. Anything that satisfies it is an implementation: a module, an object, a stub. No inheritance requirement, no registration.
- **How a thing is built is its own contract**, separate from how it is used. A caller that only uses one should not have to know what it takes to make one.
- **Name the implementations in one place.** One line assembles them and hands them on. No registry, no name-to-class table, no dotted-path lookup: a table every implementation must appear in is exactly the coupling the boundary exists to remove.
- **The neutral side may not name an implementation.** Not in an import, a string, a flag, a comment, or a test. An implementation is named where its own boundary lives, and nowhere else. The rule points outward too: the neutral side may not name a particular caller.
- **A setting belongs to whoever guarantees it.** Shared only if the protocol promises it; otherwise it belongs to the implementation that reads it, and that implementation registers it itself.
- **Check the boundary where an implementation enters.** Reject what does not satisfy it at the point of adoption, not on the first call that reaches what it lacks.
- **Keep the join narrow, and never reach through it.** Count the names one layer uses of the next. `a.b.c.setting` is one layer reaching past another; hand each side what it owns.
- **A second implementation is the proof.** One implementation cannot show whether a protocol describes the boundary or the thing behind it. A deliberately trivial second one belongs in the tests, and built differently from the first.
- **One responsibility per module and per function.** Keep units small enough to hold in your head.

## Naming

A name is the one piece of documentation nobody can skip, so it carries the
weight a comment would have carried. This applies to every name: functions,
parameters, variables, constants, types, modules, files and tests.

- **Say what it is, not that it exists.** `data`, `info`, `value`, `handle`, `process`, `manager`, `helper`, `util` name nothing. When the best name you have is one of those, you do not yet know what the thing is; find out before you write the line.
- **Say what a caller gets, not how it is done.** `use_clip` names what the caller hands over; `clone_voice` commits every implementation to cloning. The technique belongs to the implementation, and the implementation is the part that changes.
- **Name the capability, not the lifecycle stage.** `can_speak` is what a caller branches on; `voice_initialized` describes an attempt that may have rolled back. A flag is read for its outcome.
- **Use the term the field already has.** `timeout`, `retry`, `enforce`, `validate`, `backpressure`, `watchdog`. A word coined here means the reader looks up a definition before the line can be read.
- **No colloquialism and no cleverness.** Not `nuke`, `zap`, `magic`, `stuff`, `doit`, `thingy`, and no joke that survives into the tree. A name that raises a smile in review costs a second on every later read.
- **One thing, one name.** If the interface calls it `input_sample_rate`, the wire, the tests and the documentation call it that too. Two words for one thing is two things to keep in sync and a reader who has to ask whether they are the same.
- **A number carries its unit.** `timeout_s`, `max_upload_bytes`, `pause_ms`. A bare `timeout` is a defect waiting for the first caller who assumes milliseconds.
- **A boolean reads as an assertion** that is true when the value is: `can_speak`, `is_complete`, `tls`. A negated name inverts at every use site, so keep one only where a convention forces it.
- **Length follows scope.** A three-line loop takes `i`; a module-level constant is spelled out. The test is whether a reader arriving at the name has to look outside the enclosing scope to know what it means.
- **Before renaming, ask what the name identifies.** Rename what identifies this software. Leave what describes a thing in the world: a wire protocol's name, a chat role, an established acronym. And check whether the name is also a published field, because then it is a compatibility decision and not a style one.

## Universality

Names, documentation and docstrings say what is true of the thing itself.
Whatever is true only of the current implementation, or only of the machine it
was installed on, belongs in `design_history.md`.

Two questions decide every line:

- **Would this still be correct if the implementation behind the boundary were replaced?** If not, it is that implementation's business, not the interface's.
- **Would this still be correct on someone else's machine?** If not, it is a measurement, and measurements belong to the design history.

Out of names, signatures, docstrings, comments and the README:

- Product, vendor, model and library names of whatever sits behind a boundary
- The technique an implementation uses, in a name or in prose. `Naming` gives the rule; this is the reason for it, and it reaches sentences as well as names.
- Hardware: device models, core counts, memory sizes, driver and architecture versions
- Measured numbers: latencies, throughput, memory use, startup times, benchmark tables
- Absolute paths, host names and addresses of one deployment. A documented default port or cache location is the software's own and stays; the operator's machine, user and LAN address are not.
- Counts that drift on their own, such as how many tests or files there are

In, wherever it earns its place:

- What a caller may rely on, what it must do first, what it gets back, what can fail
- The invariant a value must satisfy, worded so it stays true whatever the value is
- A one-line pointer to the design-history section that holds the number

**A tuned constant keeps its name and loses its argument.** The code carries the
constraint the value must satisfy; why it is this value and what was measured to
choose it is the design history's. This is "Rationale never goes in the code",
one step further: not only the argument but the measurement.

**A fact that is genuinely an implementation's may be stated in that
implementation's own file**, and nowhere else. It still carries only the value
and a pointer, never the measurement behind it.

**Build files, deployment manifests and a README's install section cannot avoid
naming what gets installed.** They are the sanctioned exceptions. Keep them the
only ones, and keep the list short enough to state in one sentence.

`/universalize` applies all of this to a whole project.

## As simple as possible, as complex as necessary

- Nothing speculative: no feature beyond what was asked.
- No abstraction for single-use code.
- No configurability nobody requested.
- No error handling for impossible scenarios.
- If you wrote 200 lines and 50 would do, rewrite it.

## Scope of a change

Touch only what the request requires.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor what isn't broken.
- Match the surrounding style, even where you would do it differently.
- Remove the imports, variables, and helpers **your** change orphaned, and nothing else.
- Noticed unrelated dead code, or a bug outside the scope? Report it. Don't fix or delete it uninvited.

Every changed line must trace to the request.

## Readability

- **No duplicates.** Factor out repetition instead of copying it.
- **Name well.** See `Naming`. A signature that needs a comment to be understood has the wrong names in it.
- **Structure well.** Logical ordering, consistent layering, nothing left dead by your change.

## Comments vs. design history

- **Comments in code:** Google style, and sparse to the point of feeling bare. The default is no comment: write one only where the code cannot carry the information itself.
  - **A docstring is a one-line summary.** Add `Args:`, `Returns:`, `Raises:` only where the signature leaves a real question open. Prose past the summary line is the exception and needs a reason. A module docstring says what the module is in a sentence or two, never what the design argument was.
  - **An inline comment is one line**, explaining *how* something works or which non-obvious constraint the line satisfies. Never a restatement of the code, never a narration of the lines that follow.
  - **A heading over a block is wanted where it earns its line.** In a long function or a file with distinct phases, one short label lets a reader find the part they came for. The test is whether the block would otherwise have to be read to know what it does. Over a short or self-evident block, leave it out.
  - **Rationale never goes in the code.** Alternatives, measurements, and reasons belong to `design_history.md`. Where the reader needs them, name the section and stop.
- **`design_history.md`:** everything about *why*, and everything Universality keeps out of the code. Which alternatives were considered and rejected and on what grounds, benchmark numbers, measurements, hardware, trade-offs. Append a dated entry whenever a non-obvious decision is made or revised.
  - It belongs in the project folder it documents, never outside it, so it is versioned with the code it explains. Where the project is not a repository yet, the file still goes there and lands in the repository when one is created.
  - If a project already keeps this under another name (e.g. `docs/design-notes.md`), write there instead of creating a second file.
- **When code and its documentation disagree, decide which is wrong before changing either.** Often the sentence is wrong and the code is right.

## Prose style

Applies to every piece of text written into a file: docstrings, comments, documentation, `design_history.md`, and commit messages. A docstring is held to it exactly as documentation is.

- **Professional and precise.** Carry the information the reader needs, and state it exactly. No emojis, no decorative symbols, no filler.
- **Plain technical register.** Write the way a reference manual writes: state what is true and why it matters. No metaphor where a literal term exists, no personified code, no aphorism. A sentence the reader has to decode twice has failed, however well it reads.
- **No colloquialism.** Not "a bit", "pretty much", "kind of", "you would think", "nasty", "blows up", "for free", "a trap". Write the sentence a reference manual would print. This is not formality for its own sake: an idiom costs every reader who is reading at speed, and most of them cost a non-native reader more than that.
- **Understandable on the first read.** The common word over the rare one, one idea per clause, and the subject near its verb. Precision that has to be decoded twice is not precision.
- **Established jargon yes, invented jargon no.** Words the field already shares carry their meaning to any reader. A word this project coined means looking up its definition before the sentence can be read.
- **Never an em dash (U+2014).** Not inside a sentence, not as a separator, nowhere.
- **No dashes inside sentences.** Where one would join or interrupt clauses, use a comma, a colon, parentheses, or two sentences. Natural language over punctuation tricks.
- Structural hyphens are untouched: compound words, list bullets, CLI flags, and separator lines between sections stay as they are.
