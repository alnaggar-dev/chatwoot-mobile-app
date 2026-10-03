---
name: prototype
description: Make a throwaway prototype to flush out a design before committing to it: a runnable terminal app for state/business-logic questions, or several radically different UI variations toggleable from one route. Use when the user wants to prototype, sanity-check a data model or state machine, mock up a UI, or try a few designs.
disable-model-invocation: true
---

# Prototype
A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch
- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md): a tiny interactive terminal app that pushes the state machine through hard cases.
- **"What should this look like?"** → [UI.md](UI.md): several radically different variations on one route, switched by a URL search param and a floating bar.

Ambiguous and the user unreachable → pick the branch matching the surrounding code (backend module → logic; page or component → UI) and state the assumption at the top of the prototype.

## Rules for both
1. **Throwaway and clearly marked.** Next to the module or page it prototypes, named so a reader sees it's a prototype; UI routes follow the project's routing convention. Every prototype file, each sub-shape A variant and the host-page lines mounting the switcher carry a comment containing `PROTOTYPE-THROWAWAY`; `.superflow/bin/ship-check.sh` fails, and ship refuses, while any remains.
2. **One command to run** (a package script, a make target, one interpreter call on a file, …).
3. **No persistence by default.** State in memory; if the question involves a database, a scratch DB or a local file named "PROTOTYPE — wipe me". A variant that needs to mutate points at a stub.
4. **Skip the polish.** No tests, no error handling beyond runnable, no abstractions.

## When done
Keep only the answer:
- **Sharpens vocabulary** → update `CONTEXT.md` (format: `.superflow/skills/formats/CONTEXT.md`).
- **A non-obvious decision** meeting the ADR criteria (`.superflow/skills/formats/ADR.md`) → offer an ADR.
- **Feeds a feature** → write the answer into `features/<slug>/PRD.md` under `## Decisions` as a self-contained decision line, replacing that topic's `open` line. Land the decision itself, not a pointer to prototype code; where prose is imprecise, inline the trimmed decision-rich snippet (state machine, schema, type shape), marked prototype-derived. `/flow <slug>` then resumes.
- **None of these** → put the answer in the commit message that deletes the prototype.

Then delete the throwaway code, or fold its validated logic module into the real codebase; the TUI shell and variant switcher never stay.
