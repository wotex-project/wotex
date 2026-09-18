# Decision 0008: Generate built-in and static documentation from one corpus

## Decision

Wotex Lab assembles the ecosystem documentation through DocShell and renders it
with the Phoenix Assets LiveView adapter. The Workbench and public static site
consume one projected site generation. Static publication does not use a
second Astro, mdBook, GitBook, or application-specific template tree.

Each package, and each documentation-only source, is extracted separately,
from one commit of the repository. Lab imports the resulting versioned
artifacts and applies one Wotex taxonomy. This keeps package locks and runtime
dependencies isolated while preserving exact source provenance. (Amended for
the monorepo with WLB.12 0.2.0; the packages were separate repositories when
this decision was taken.)

## Rationale

The Wotex documentation includes BEAM module documentation, Markdown,
Livebooks, OpenAPI, specifications, evidence and project guidance. DocShell
already normalizes those source kinds. A second content pipeline would create
another schema and another place for navigation and links to diverge.

Mature static documentation systems establish a useful user-experience floor:
responsive hierarchical navigation, keyboard search, table of contents,
themes, localization, source links, reading flow, code tools, structured
content and static SEO. Those capabilities are accepted as renderer behavior,
without importing another framework into the LiveView host.

Phoenix function components can render in LiveView and as HTML-safe iodata.
Using the same components for static export keeps the content and accessibility
structure aligned. Browser enhancement is shared through a framework-neutral
Phoenix Assets entry so the static site does not require a LiveSocket.

## Consequences

- DocShell owns multi-corpus site semantics and static-export behaviours.
- Phoenix Assets owns Svelte and LiveView renderers and their shared browser
  behavior.
- Lab owns only source membership, taxonomy, branding, routes and deployment.
- Public and release documentation disclose exact cohorts.
- A failed build retains the preceding complete static site.
- Hosting remains replaceable because the output is an ordinary static
  directory.
