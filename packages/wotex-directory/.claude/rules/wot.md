---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "docs/**/*.md"
---

# W3C Web of Things rules

- Use Thing, Property, Action, Event, Thing Description, DataSchema, Form, and
  security scheme with their W3C meanings.
- The production target is Thing Description 1.1 and WoT Discovery, both dated
  2023-12-05.
- The Discovery context is `https://www.w3.org/2022/wot/discovery`.
- The Thing Description media type is `application/td+json`.
- Enriched Thing Descriptions preserve extension terms through the core value
  model.
- This package owns Discovery registration metadata, not base Thing Description
  semantics.
- JSONPath and XPath search are informative Discovery features; SPARQL search is
  optional. Do not claim or emulate them without a separate accepted contract.
