# Wiki Schema

> [!TIP] Tip
> 设计原理见 LLM_WIKI.md（仅供需要时查阅，日常维护无需读取）

## Page types

- `concept`: an idea, pattern, or mechanism (e.g. how auth tokens flow).
- `entity` : a concrete thing (a service, a module, a tool, a person/team).
- `decision`: a choice made and why (architecture calls, trade-offs taken).
- `pitfall` : a bug/gotcha and its resolution (postmortems, debugging notes).
- `summary` : a periodic rollup (phase summary, sprint retro).
- `context`: expected context space required for reading. (unit: k)

## Frontmatter (required on every 编译 page)

```yaml
---
title: <short, specific title>
type: concept | entity | decision | pitfall | summary
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [源资料/file1.md, 源资料/file2.md]
topic: <topic>
tags: [tag1, tag2]
status: current | superseded | contested
context: 16
---
```

## Naming

- File name = kebab-case of the title. One topic per file. Split rather than
  let a page sprawl across unrelated topics.

## Cross-references

- Link related pages with relative markdown links inline where the concept is
  mentioned. A page introducing a new concept should link back to pages that
  depend on it, and vice versa (backlinks are not automatic — add them).

## Contradiction handling

- Never silently overwrite a superseded claim. Mark the old claim
  `status: contested` or `superseded`, note the new claim with its source,
  and keep both visible until a human resolves it.

## INDEX

One line per page:

```
# Topic

[<title>](simple-wiki/wiki/<file>.md) | <one-line summary> | tags: <tag1, tag2>
```

## Staleness

- A page is stale if its 源资料 predates a newer, unreconciled source on the
  same topic. Flag in LINT; do not auto-resolve.
