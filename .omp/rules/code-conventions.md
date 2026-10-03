---
description: Code conventions for this repo; tdd and final-review judge code against them.
---

- Production path first: no speculative guards, fallbacks or retries. Enforce an eligibility or exclusivity rule once, at the earliest shared entry point, with no backup guards downstream (jobs, callbacks, writes) unless a proven independent path bypasses it. A guard the brief's Decisions demand is required, placed once at the boundary, not repeated downstream. Required config is read directly and fails loudly when missing.
- Request input: validate parameters at the boundary where they enter (request handler, CLI parser, message consumer), reusing the project's existing errors, so invalid input gets a clear client error instead of reaching the domain or the error tracker. Accept only the documented type, shape and values: no compatibility coercions for malformed client values; fix the client instead.
- Prefer the project's existing dependencies and client libraries over hand-rolled protocol code for auth, signing, parsing or API plumbing.
- Repeated strings, thresholds, colors and durations become named constants.
- Tests: test behavior through public interfaces, not internals; mock only at system boundaries (external APIs, time, the network), never our own code; expected values are hand-computed or come from an independent source, never recomputed the way the code computes them.
- Formatting is Prettier (`.prettierrc`: single quotes, trailing commas, print width 100, `arrowParens: avoid`), enforced through ESLint's `prettier/prettier` rule on top of the `expo` config (`.eslintrc.js`).
- Import app code through the `@/` alias for `src/` (`jest.config.js`, `tsconfig.json`); unit tests sit in a `specs/` folder beside the module named after it (`rtlUtils.ts` → `specs/rtlUtils.spec.ts`).
