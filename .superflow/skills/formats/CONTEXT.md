# CONTEXT.md format

```
# <Product>
<one or two sentences: what this product is>

## Language
**<Term>**:
<one sentence: what it is, not what it does>
_Avoid_: <synonyms>

## Relationships          (optional)
- A **<Term>** has one or more **<Term>s**

## Example dialogue       (optional)
> **Dev:** "<question using the terms>"
> **Domain expert:** "<answer that draws a boundary>"

## Flagged ambiguities    (optional)
- "<word>" meant both **<Term>** and **<Term>**: resolved, <resolution>.
```

- One word per concept; list the others under `_Avoid_`.
- Only terms specific to this product; no general programming terms.
- Group terms under subheadings when clusters emerge.
- Ambiguous term → resolve it and note the resolution under `## Flagged ambiguities`.
