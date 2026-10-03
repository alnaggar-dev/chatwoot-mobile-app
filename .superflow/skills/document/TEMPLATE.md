# <Feature name>
<!-- Fill in; delete sections that do not apply and every comment. -->

<1–3 sentences: what it is, why it exists, the core mechanism, what gates it (feature flag, setting, role, plan), and, in a fork install when the feature has a ledger entry, "registered as `<slug>` in [`.fork/CHANGES.md`](../.fork/CHANGES.md)" (fork-change fills this).>

- **<Concept>** — <one line; the nouns the rest of the doc reuses, matching CONTEXT.md>

> **Operator note:** <what and where> — runbook: [<operations doc> §<section>](<operations-doc>.md). <!-- only when an operator must act -->

## Key files

| Path | Role |
| --- | --- |
| [`src/<area>/<entry>`](../src/<area>/<entry>) | <role> |

## Constants and persisted contract

| Constant / field | Value | Source |
| --- | --- | --- |
| `SOME_CONSTANT` | `'value'` | [`src/<area>/<entry>`](../src/<area>/<entry>) |

## Data model
- `<table, collection or type>` — fields, defaults, unique indexes.
- Invariant: <always holds>.

## Routes and API shape

| Route | Handler | Contract |
| --- | --- | --- |
| `POST /<resource>/:id/<action>` | `<module>.<function>` | <params → response> |

## How <the main flow> works

```text
input
  ├─ <condition>? ── yes ──> <path A>
  └─ no ──────────────────> <path B>
```

1. <step — `<module>.<function>`>

## Feature gates and exclusions

| Area | Gate |
| --- | --- |
| <area> | <flag / setting / role> |

## Failure handling

| Case | Behavior |
| --- | --- |
| <what goes wrong> | <fallback, retry, notification> |

## What it does / does NOT do
- Can: <…>
- Does NOT: <…> ([ADR NNNN](adr/NNNN-slug.md)).

## Verification map
The `<slug>` entry's Verify and Check live in [`.fork/CHANGES.md`](../.fork/CHANGES.md). <!-- fork-change fills this in a fork install when the feature has a ledger entry; otherwise delete this line -->

| Test path | Coverage |
| --- | --- |
| `<tests>/<area>/<thing>` | <behavior it proves> |

<!-- One block per browser journey, for Done-when items with `Proof: browser`; `verify` reads it to set up and drive the app. Setup is only what the **Seed data** command does not make, as a snippet for the **Run a setup snippet** command (`.omp/rules/commands.md`) that is safe to run on an existing database: find-or-initialize / upsert by a natural key, never a plain create, never re-seed. Steps name an existing end-to-end page object or helper where one exists; never copy selectors out of component source. -->
### Browser journey: <flow name>
- **Reach**: <route or menu path>; <role>; <flag or setting>.
- **Setup**: <flags, plan limits, keys, records the seed data does not make>.
  ```text
  owner = find <owner> by <natural key>          (fail if missing)
  enable <flag> on owner
  upsert <record> where <key> = <value>, set <attrs>
  ```
- **Steps**: <click path, or the page object that drives it>.
- **Finished result**: <what the screen shows>; <what the database or log holds afterwards>.
