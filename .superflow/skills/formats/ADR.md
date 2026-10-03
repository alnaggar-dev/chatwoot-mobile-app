# ADR format

`docs/adr/NNNN-slug.md`, next number after the highest; create `docs/adr/` with the first one.

```
# <decision, as a sentence>

Status: <accepted; superseded by [ADR-NNNN](NNNN-slug.md)>   (only when superseded or deprecated)

<context, what we decided, why: a paragraph is enough>
```

Optional sections as needed, e.g. `## Considered options`, `## Rejected`, `## Consequences`.

Offer one only when all three hold: hard to reverse; surprising to a reader without context; the result of a real trade-off.
