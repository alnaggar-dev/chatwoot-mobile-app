# UI Prototype
Generate **several radically different UI variations** on a single route, switchable from a floating bottom bar. The user flips between variants, picks one (or steals bits from each), throws the rest away.

## Two sub-shapes — strongly prefer sub-shape A
Variants are judged against the rest of the app — real header, sidebar, data and density; on a standalone route every variant looks fine.

### Sub-shape A — adjustment to an existing page (default)
The route already exists. Variants render **on the same route**, gated by a `?variant=` URL search param. Existing data fetching, params, and auth all stay — only the rendering swaps. Something that has no page yet but *would naturally live inside one* (new dashboard section, new settings card, new step in a flow) is still sub-shape A: mount the variants inside the host page.

### Sub-shape B — a new page (last resort)
Only when the thing genuinely has no existing page to live inside — an entirely new top-level surface, or a flow that can't be embedded anywhere sensible. Create a **throwaway route** following the project's existing routing convention, named so it's obviously a prototype (include `prototype` in the path or filename). Same `?variant=` pattern, same floating bottom bar as sub-shape A.

## Rules
- Every variant file, the switcher, a sub-shape B route and the host-page lines mounting the switcher carry a comment containing `PROTOTYPE-THROWAWAY`; `.superflow/bin/ship-check.sh` fails while any remains.
- A variant that needs to mutate points at a stub: the question is "what should this look like", not "does the backend work".

## 1. Pick N
Default to **3 variants**; more than 5 stops being radically different and starts being noise — cap there.

## 2. Generate radically different variants
Variants must be **structurally different** — different layout, different information hierarchy, different primary affordance, not just different colours. Two drafts too similar → redo one with explicit "do not use a card grid" guidance.

## 3. Wire them together
Read `variant` from the URL search param (default `A`). Sub-shape A: all existing data fetching stays above the switcher; only the rendered subtree changes per variant.

## 4. Switcher
A fixed pill at the bottom centre: ← variant label →, wrapping. Arrows and the ← → keys set `?variant=` through the router (never while an input, textarea or contenteditable has focus). Show it only outside production builds, so a stray prototype merge can't ship the bar to users; check the flag is actually false in the dev mode you run the app in (some build tools set production mode for dev builds too, and the bar would never show). Keep it next to the variants, never in shared UI; it is deleted with them.

## 5. Hand it over
Bring the app up and drive it through `verify` steps 2–5 (Start, Seed, Drive, Proof), open each `?variant=` on the route yourself and screenshot it (under `$(git rev-parse --git-dir)/superflow/prototype/`). Hand over those screenshots with the URL and the `?variant=` keys.

## 6. Clean up
After **When done** in [SKILL.md](SKILL.md):
- **Sub-shape A** — delete the losing variants and the switcher; fold the winner into the existing page.
- **Sub-shape B** — promote the winning variant to a real route; delete the throwaway route and the switcher.
- Rewrite the winner properly when folding it in — it was written under prototype constraints. Shared `<Header>` between variants is fine; a shared layout defeats the point.
