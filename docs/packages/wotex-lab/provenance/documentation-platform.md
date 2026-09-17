# Documentation platform references

The WLB.12 acceptance contract uses these upstream references for capability
and deployment behavior. They do not become runtime dependencies of
`wotex_lab`.

| Reference | Adopted behavior | Excluded coupling |
| --- | --- | --- |
| [Starlight overview](https://starlight.astro.build/) | Navigation, search, internationalization, SEO, typography, code highlighting and themes as a product baseline | Astro application and content routing |
| [Starlight sidebar](https://starlight.astro.build/guides/sidebar/) | Nested/collapsible groups, ordering, badges and localized labels | Filesystem-derived Wotex taxonomy |
| [Starlight search](https://starlight.astro.build/guides/site-search/) | Search on every static page and explicit search exclusion | Hosted Algolia dependency |
| [Starlight page metadata](https://starlight.astro.build/reference/frontmatter/) | Description, source/edit link, table of contents, template, last-updated, reading flow, draft/search/sidebar visibility | Raw renderer-specific head configuration |
| [Pagefind](https://pagefind.app/) | Optional chunked, multilingual, filtered static search model | Required Node/native runtime or hosted service |
| [Phoenix components](https://hexdocs.pm/phoenix/components.html) | Shared HEEx function components for controller and LiveView rendering | A second frontend framework |
| [LiveView JavaScript interoperability](https://hexdocs.pm/phoenix_live_view/js-interop.html) | Thin refresh hook around framework-neutral browser enhancement | LiveSocket requirement for static pages |
| [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) | Build artifact followed by separately permissioned deployment | Generated publication commits |

GitHub documents Pages availability for public repositories on GitHub Free and
GitHub Free for organizations. Custom domains and Pages repository settings are
maintainer configuration and are not changed by the implementation.
