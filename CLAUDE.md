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
- **When an invariant changes, the old one is dead.** Remove the checks that enforced it and update whatever documented it.

Record *why* an invariant holds, and what it rules out, in `design_history.md`, not in a comment at each site.

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
- **Modularize.** One responsibility per function or module; keep units small enough to hold in your head.
- **Name descriptively.** Signatures, variables, and parameters should say what they are without a comment.
- **Structure well.** Logical ordering, consistent layering, nothing left dead by your change.

## Comments vs. design history

- **Comments in code:** Google style, and sparse to the point of feeling bare. The default is no comment: write one only where the code cannot carry the information itself.
  - **A docstring is a one-line summary.** Add `Args:`, `Returns:`, `Raises:` only where the signature leaves a real question open. Prose past the summary line is the exception and needs a reason. A module docstring says what the module is in a sentence or two, never what the design argument was.
  - **An inline comment is one line**, explaining *how* something works or which non-obvious constraint the line satisfies. Never a restatement of the code, never a narration of the lines that follow.
  - **A heading over a block is wanted where it earns its line.** In a long function or a file with distinct phases, one short label lets a reader find the part they came for. The test is whether the block would otherwise have to be read to know what it does. Over a short or self-evident block, leave it out.
  - **Rationale never goes in the code.** Alternatives, measurements, and reasons belong to `design_history.md`. Where the reader needs them, name the section and stop.
- **`design_history.md`:** everything about *why*. Which alternatives were considered and rejected and on what grounds, benchmark numbers, measurements, trade-offs. Append a dated entry whenever a non-obvious decision is made or revised.
  - If a project already keeps this under another name (e.g. `docs/design-notes.md`), write there instead of creating a second file.

## Prose style

Applies to every piece of text written into a file: comments, documentation, `design_history.md`, and commit messages.

- **Professional and precise.** Carry the information the reader needs, and state it exactly. No emojis, no decorative symbols, no filler.
- **Never an em dash (U+2014).** Not inside a sentence, not as a separator, nowhere.
- **No dashes inside sentences.** Where one would join or interrupt clauses, use a comma, a colon, parentheses, or two sentences. Natural language over punctuation tricks.
- Structural hyphens are untouched: compound words, list bullets, CLI flags, and separator lines between sections stay as they are.
