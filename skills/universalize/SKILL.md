---
name: universalize
description: Sweep a whole project so that every name, signature, docstring, comment and document says only what stays true when an implementation behind a boundary is replaced or the project is installed on another machine. Moves hardware facts, measurements and implementation specifics into the design history.
---

# [Universalize]

One pass over an **entire project**, not one change. It ends with every name and
every sentence in the tree passing two questions:

1. **Would this still be correct if the implementation behind the boundary were replaced?**
2. **Would this still be correct on someone else's machine?**

Whatever fails a question is either rewritten to say the thing that survives, or
moved into the design history, or deleted because the design history already has
it. Nothing is silently dropped.

The rules being applied are `Modularity`, `Naming`, `Universality`, `Comments
vs. design history` and `Prose style` in `~/.claude/CLAUDE.md`. Read them
first; this skill is how they get applied at project scale.

Sweeping a whole tree is the request here, so `Scope of a change` in
`~/.claude/CLAUDE.md` does not apply the way it usually does. What still holds
is its reason: every changed line must trace to one of the two questions above.
A line that passes both and that you would merely have written differently
stays as it is.

## 0. Agree the scope before touching anything

This rewrites names a caller may depend on, so settle these with
`AskUserQuestion` and do not guess:

- **Where are the boundaries?** Which protocols, interfaces or module edges are
  the seams, and what counts as "behind" each one. Everything else follows from
  this answer.
- **What is on the wire or otherwise published?** Error codes, field names,
  message types, CLI flags, environment variables, file formats. Renaming one is
  a compatibility decision, not a style decision.
- **Which files are the sanctioned exceptions?** Build files, deployment
  manifests, the install section of a README. They name what gets installed
  because they cannot avoid it. Name them explicitly, and keep the list short.
- **Where does the design history live?** `design_history.md`, or whatever the
  project already calls it. Everything removed lands there.
- **How far do renames go?** Public names, or private ones too. Test names.

If the project has no design history file yet, that is the first thing to
create: this skill moves facts into it and will not delete them instead.

## 1. Inventory

Build the list before changing anything, so the size of the job is known and
nothing is found halfway through.

Search the whole tree, excluding generated files and the sanctioned exceptions.
Adapt the patterns to the project's own vocabulary.

**Implementation names behind a boundary**

```
# every vendor, product, model and library name of what sits behind a seam
grep -rniE '<engine>|<vendor>|<library>' --include='*' .
```

Take the list of names from step 0 rather than inventing it. The neutral side
must not carry one, in an import, a string, a flag, a comment or a test.

**Every name, against the `Naming` rules**

Names are the half of this that no reader can skip, so extract them all rather
than noticing the ones that happen to catch your eye:

```
# every defined name, deduplicated. Adapt to the language.
grep -rhoE '\b(def|class) [A-Za-z_][A-Za-z0-9_]*' --include='*.py' . | sort -u
# every parameter and local worth reading
grep -rhoE '^\s+[a-z_][a-z0-9_]* *[:=]' --include='*.py' . | sort -u
# every flag, environment variable and published field
grep -rhoE '"--[a-z-]+"|\bos\.environ[^)]*"[A-Z_]+"' -r . | sort -u
```

Take each through the checklist, in this order, because the earlier questions
decide the later ones:

1. **Does it name nothing?** `data`, `info`, `handle`, `manager`, `helper`,
   `util`, `process`. These are the cheapest to find and the most costly to keep.
2. **Does it name a technique instead of what a caller gets?** `clone_voice`
   commits every implementation to cloning; `use_clip` names what the caller
   hands over.
3. **Does it name a lifecycle stage instead of a capability?**
   `voice_initialized` describes an attempt; `can_speak` describes the outcome a
   caller branches on.
4. **Is it a word this project coined?** If a reader needs a glossary entry, the
   field's own term replaces it.
5. **Is it colloquial, or a joke?** It costs a second on every read after the
   one that enjoyed it.
6. **Does the same thing have a second name elsewhere?** One name across the
   interface, the wire, the tests and the documentation.
7. **Does a number carry its unit?** `timeout_s`, `max_upload_bytes`.
8. **Is a boolean asserted rather than negated?** A negated name inverts at every
   use site.
9. **Is it published?** Then a rename is a compatibility decision. Take it back
   to step 0 rather than deciding it here.

**Colloquialism, in names and in prose**

```
grep -rniE "\b(a bit|pretty much|kind of|sort of|you would think|you'd think|nasty|ugly|blows? up|for free|a trap|magic|clever|nuke|zap|stuff|thingy|doit)\b" .
```

The list is a starting point, not a definition. What you are looking for is any
sentence a reference manual would not print, and any name that reads as spoken
rather than written.

Expect false positives and keep them. `magic bytes` is the standard name for a
file signature, `magic constant` is how RFC 6455 words it, and `what kind of
resource` is the noun rather than the idiom. A word is colloquial in one use
and technical in another, so read the line before touching it.

**Hardware and environment**

```
grep -rniE '\b(GPU|VRAM|CUDA|RTX|GeForce|Radeon|core count|[0-9]+ *(GB|MB|MiB|GiB))\b' .
grep -rniE '\b(x86|arm64|avx|compute[_ ]cap)\b' .
```

**Measurements**

```
# numbers with a time unit, in prose or in a comment
grep -rniE '[0-9]+([.,][0-9]+)? *(ms|s|sec|seconds|minutes|tok/s|fps|Hz)\b' .
# tables of measured results
grep -rn '^|' --include='*.md' .
```

A number that is a *bound the code enforces* stays. A number that is a
*measurement of this machine* goes. `timeout_s: 30` stays; "measures 12 s on a
warm start" goes.

**One deployment's addresses**

```
grep -rniE '([0-9]{1,3}\.){3}[0-9]{1,3}|localhost:[0-9]+|/home/[a-z]+|C:\\\\' .
```

**Counts that drift**

```
grep -rniE '\b(tests?|passed|skipped|files|modules|endpoints|containers)\b' --include='*.md' .
```

A count rarely sits next to the word that names it, so no pattern finds them
reliably: `# 244, where all three engines are installed` matches nothing you
would think to search for. Grep finds the topic; you read the lines and
re-derive each number yourself. A document says what a thing is, not how many
of it there are today.

**Register**

Docstrings and prose that read as essay rather than reference: metaphor where a
literal term exists, personified code, aphorism. Extract them mechanically where
the language allows, so none is missed:

```
python3 -c "
import ast, sys
from pathlib import Path
for f in Path('.').rglob('*.py'):
    for n in ast.walk(ast.parse(f.read_text())):
        if isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef)):
            d = ast.get_docstring(n, clean=False)
            if d: print(f'--- {f}:{getattr(n, \"lineno\", 1)}'); print(d.rstrip())
"
```

Write the inventory down, grouped by the decision each item needs: **rewrite**,
**move**, **delete**, **keep (exception)**. Report its size to the user before
starting step 2 if it is large.

## 2. Names and signatures first

Names come before prose, because prose that describes a name has to be written
once, not twice.

- Work the checklist above in its own order. A name that fails question 1 is
  usually still wrong after you fix question 7, so settle what the thing *is*
  before you polish how it is spelled.
- Rename by exact token, with word boundaries, across every file type at once,
  including tests, documentation, configuration and the design history.
- Handle names that hide the word inside an identifier separately:
  `test_a_press_is_dropped` does not match `\bpress\b`. Enumerate those.
- After each family of renames, grep for the old token again. Zero hits, or an
  explicit list of the ones that are meant to stay (a historical entry in the
  design history, a verb that happens to be the same word).
- Run the tests. A rename that compiles is not a rename that works.

Watch for two failure modes the mechanical pass creates:

- **A phrase that no longer parses.** "how long a caller may press" becomes "how
  long a caller may recording". Read every changed prose line, not just the
  changed identifiers.
- **A new collision.** The replacement word may already mean something else in
  the tree. Check it before, not after.

## 3. Move the facts, then remove them

For every **move** in the inventory, in this order:

1. Write the fact into the design history first, in a dated entry, with the
   measurement, the hardware it was measured on, and what it decided.
2. Only then remove it from the code or the README.
3. Leave a one-line pointer where the reader will need it: name the section and
   stop.

Never the other way round. A fact deleted before it is recorded is lost, and the
diff will not show you that it was.

Group related facts into one entry rather than scattering them. A table of what
moved, and where it went, is usually the clearest form.

## 4. Rewrite the prose

Docstrings, comments, README, and any other document.

- **A docstring is a one-line summary**, then paragraphs only where they earn
  their place. Convert every summary that wrapped onto a second line.
- **State what a caller may rely on**: what it must do first, what it gets back,
  what can fail. Not what the current implementation does inside.
- **Replace, do not delete, the information.** Where a sentence carried a fact,
  the fact stays and only the figure of speech goes.
- **Prefer the ordinary word.** Established jargon (`seam`, `backpressure`,
  `watchdog`, `keepalive`) carries its meaning to any reader; a word this project
  coined does not.
- **No colloquialism.** The register is a reference manual's: professional,
  technical, and understandable on the first read. Not stiff, and not chatty.
  An idiom costs every reader who is reading at speed.
- **A docstring describes the interface, not the implementation behind it.**
  What the caller must do first, what it gets back, what can fail. A sentence
  that would need rewriting when the implementation is replaced does not belong
  in it.
- Keep the line width and wrapping the surrounding file uses.

## 5. Verify

Everything here has to actually run, and its real result reported.

- **The tests**, in every configuration the project supports. If which tests can
  run depends on what is installed, run each configuration and report each
  count. Report them to the reader of this run; they do not go back into the
  documents you just took them out of.
- **Every entry point**, by invoking it. `--help` on each is enough to catch an
  import a rename broke. This is where a rename most often fails silently,
  because nothing else imports an entry point.
- **Cross-references resolve.** Every "see design history, X" names a section
  that exists. Extract and check them mechanically.
- **Documented paths exist.** Every repository-relative path named in a document
  is either present or explicitly historical.
- **Nothing was lost.** For each item marked *move* in the inventory, confirm the
  design history now holds it.
- **The old vocabulary is gone.** Re-run the step 1 searches. Explain every
  remaining hit.
- **No undefined names.** Where the language has no compiler, sweep for globals
  that are used and never bound. A rename that deletes an import fails only at
  call time.

## 6. Record the decision

A dated entry in the design history covering the sweep itself: which words
changed and to what, which were deliberately kept and why, anything published
that changed and how compatibility was handled.

The kept list matters as much as the changed one. Without it the next reader
re-opens the same question.

## 7. Report

```
[Universalize]
Scope:     <boundaries, published surface, exceptions, design-history file>
Inventory: <n rewrite, n move, n delete, n kept>
Renamed:   <one line per name family: old → new, and why>
Moved:     <what went into the design history, and under which entry>
Prose:     <what the register pass changed>
Ran:       <every check from step 5, with its actual result>
Published: <what changed on the wire or the CLI, and the compatibility call>
Open:      <what needs a decision, or "nothing">
```

Then invoke `/check` on the result. This skill rewrites more of a tree at once
than any other, and a mechanical sweep is exactly the kind of change whose
damage hides in the lines next to the ones it meant to touch.
