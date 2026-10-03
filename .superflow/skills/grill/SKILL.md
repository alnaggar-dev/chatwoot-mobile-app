---
name: grill
description: Interview the user to stress-test a feature idea, sharpen its terms, update CONTEXT.md and ADRs, and write decisions into the brief features/<slug>/PRD.md. Also for vocabulary with no feature.
---

# Grill

1. **One active feature.** Once there is a feature, pick a kebab-case slug; `.superflow/bin/feature-branch.sh --check <slug>` before writing; it fails → stop and ask. No feature (a stress test, vocabulary only) → no slug, no folder: steps 2 and 3 only.

2. **Interview.** Ask the whole frontier (every decision whose prerequisites are settled) in one round: number the questions, give each 2–4 real options and your recommended answer with a one-line reason, then wait. Repeat until the frontier is empty and the user confirms you share the picture.
   - Facts are yours: look them up in the code or send a scout. Decisions are the user's.
   - An answer with no real alternative → state it, don't ask.
   - Challenge: terms that clash with `CONTEXT.md`; fuzzy or overloaded words (probe with concrete edge cases); claims about how the code works (check them); in a fork install (`.fork/CHANGES.md` exists), which upstream files the feature touches and how, against `AGENTS.md` Fork rules → **Customizations**; and, while still open, whether the feature should exist at all.
   - Scope widening instead of sharpening → say so. Prose that cannot settle a design → suggest `/prototype`.

3. **Docs inline.** Update `CONTEXT.md` the moment a term resolves (format: `.superflow/skills/formats/CONTEXT.md`). Offer an ADR only when it meets the ADR criteria and format in `.superflow/skills/formats/ADR.md`; read them first.

4. **Brief as you go.** Write each settled decision into `features/<slug>/PRD.md` before the next question, in the format of the `flow` skill's `## The brief` section; decisions the user makes are `Yours`. Amend an existing brief; change a decision only when the user does. Point at what `CONTEXT.md` or an ADR holds; don't copy it.

5. **Hand off.** "Brief at `features/<slug>/PRD.md`. Next: `/flow <slug>`."
