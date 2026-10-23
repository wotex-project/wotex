# Dependency review: 23 October 2026

This refresh follows frontend commit `ba13b940`. All twenty package locks,
three Lab host locks and the documentation collector were resolved with
`mix deps.update --all` after reviewing the published package archives and
upstream changelogs. The root Hex lock was already current. Requirements on
published family packages and the explicit development path switch are unchanged.
Historical source, archive and browser receipts keep their original inputs.

DocShell 0.5 activates the projector's existing conditional `SiteSource`
behavior. Regenerating the public API snapshot changes only that behavior
metadata; exported functions, structs and typespecs are unchanged. Dialyzer
now includes DocShell so it can check the callback contract. The Phoenix
Storybook version assertion tracks the reviewed 1.5.0 release.

## Selected updates

| Dependency | Selected version | Reason and compatibility decision |
| --- | --- | --- |
| DocShell | 0.5.0 | Adopt renderer-neutral site support and portable redirect tracking; preserve the collection extraction API. |
| ExCheck | 0.17.1 | Adopt unknown-tool diagnostics without changing the configured gate set. |
| Phoenix / LiveView | 1.8.16 / 1.2.13 | Adopt connection race, hooked SVG and form recovery fixes. The hosts continue bundling their locked dependency assets. |
| Phoenix Storybook | 1.5.0 | Adopt release-path, asset-hash, layout and navigation fixes. No installer is run. |
| PhoenixTest Playwright / PlaywrightEx / Playwright | 0.19.0 / 0.15.0 / 1.64.1 | Keep the Elixir client and browser protocol on the required 1.64 baseline; preserve existing finite timeouts. |
| Svelte | 5.57.2 | Adopt derived-state lifecycle, subscription and native input value fixes. |
| Vite / Storybook | 8.3.5 / 10.6.3 | Adopt preload/base-path and build fixes; preserve existing configuration and accessibility checks. |
| TypeScript API | `@typescript/typescript6` 6.0.2, underlying compiler 6.0.3 | Use Microsoft's maintained compatibility alias because the AST gates and Svelte checker consume the JavaScript compiler API. |
| Node types | 26.6.5 | Apply the compatible declaration patch. |
| Circuits UART | 1.7.0 | Invalid parity/data/stop-bit configurations now fail explicitly instead of being silently ignored. Existing adapter error propagation and default 8N1 settings remain. |
| Exqlite / h2 | 0.43.0 / 0.12.5 | Adopt the compatible SQLite wrapper and HTTP/2 updates. Do not widen flow-control defaults implicitly. |
| CAStore / MDEx native / Zoi | 1.0.22 / 0.2.12 / 0.19.0 | Refresh certificate data, Markdown native support and upstream schema fixes without changing host admission rules. |
| Nerves Discovery / UEvent | 0.1.6 / 0.1.8 | Adopt off-link mDNS filtering and the statistics-loop fix in the host dependency closure. |

## Versions retained

Phoenix Assets 1.2.1 was installed and exercised against the reader tests.
It supplies the portable renderer but lacks the `presentation: :inline`,
`trigger`, header/control slots and supplied filter-value API required by the
accepted compact reader. Two reader tests failed. Keep 1.1.1 until a compatible
published renderer exists; neither a dependency bump nor passing unrelated
checks closes WLB.12. The existing reader compatibility assertions are unchanged.
DocShell 0.5.0 alone does not provide that Phoenix renderer seam.

Nx 1.0, EXLA 1.0, Axon 0.9, Explorer 0.13 and Complex 1.0 form a coordinated
numerical migration beyond the current qualified Nx 0.13.1 cohort. Nx removes
hooks and deprecated tensor APIs; Explorer changes first-sample missingness,
single-element covariance and CSV dtype interpretation. This refresh preserves
that cohort and its exact-value comparison policy. XLA remains constrained by
EXLA. TypeScript 7's native compiler is likewise not a drop-in compiler API.

The Nerves rpi4 2.1.2 system pin and its Buildroot closure remain unchanged;
a host check cannot qualify a new firmware image. Lua, Peep, Makeup HTML,
Certifi, Quicer, Uniq and Const Enum remain within their upstream consumers'
requirements. No forced overrides or advisory suppressions were added.

The four owned Cargo locks were audited with `cargo update --dry-run`.
Available transitive updates are recorded locally; the containment, benchmark,
register-reference and OPC UA peer snapshots remain unchanged. Their exact
native source and fixture cohorts require separate requalification. Vendored
manifests and pinned native SDK source recipes were not rewritten.

## Gate repairs

The full gates found missing internal documentation, an unannotated terminating
Runtime helper, and missing BLE lifecycle coverage. The repairs document those
functions, give the terminating helper an explicit `no_return()` type, and test
malformed native frames, late reply evidence, handoff expiry, request identity
exhaustion, queue abandonment, receiver loss and bounded close waiters. The
independent test peer can explicitly release a held write through its real pipe.
The BLE coverage floor and existing behavior assertions are unchanged.

Native checks now register the BLE archive peer with its extracted-header layout.
The Linux entry point forces the root tooling compile as one batch: Mix 1.20's
incremental export invalidation otherwise attempts to touch dependent source
files on the intentionally read-only repository mount. Dependency and build
outputs continue to use the writable native cache.

The Matter workspace verifier admitted at most 256 execution logs even though
its normal and sanitizer bridge case groups now generate 314. Admission is
bounded at 512 logs; every log still requires a safe path and matching digest,
and the manifest retains its one-MiB byte limit. Regression tests exercise the
old boundary, the expanded profile, the new boundary, over-limit refusal and
log tampering. Existing receipts are not relabelled or rewritten.

The SDK analysis also checks stable copies of optional observation values,
explicit unsupported-command defaults and an initialized field mask. Trivial
request copies no longer use ineffective moves. Test callback exceptions stay
inside their `noexcept` boundary, and unsupported commands are checked across
every selected cluster. The five affected translation units pass the same
clang-tidy configuration without new suppressions.

CoAP's native checks use the separately installed Java runtime; OPC UA uses
an actual Python interpreter ahead of version-manager shims. These are test
host prerequisites, not package dependencies or changes to the consumer API.

## Primary release guidance

- [DocShell 0.5.0](https://github.com/futhr/doc_shell/blob/v0.5.0/CHANGELOG.md)
- [Phoenix Assets 1.2.1](https://github.com/ghostshift-assembly/phoenix-assets/blob/v1.2.1/CHANGELOG.md)
- [Phoenix releases](https://github.com/phoenixframework/phoenix/blob/v1.8.16/CHANGELOG.md)
- [LiveView releases](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.13/CHANGELOG.md)
- [Phoenix Storybook releases](https://github.com/phenixdigital/phoenix_storybook/blob/v1.5.0/CHANGELOG.md)
- [PlaywrightEx releases](https://github.com/ftes/playwright_ex/blob/v0.15.0/CHANGELOG.md)
- [Svelte 5.57.2](https://github.com/sveltejs/svelte/releases/tag/svelte@5.57.2)
- [Vite 8.3.5](https://github.com/vitejs/vite/releases/tag/v8.3.5)
- [Storybook 10.6.3](https://github.com/storybookjs/storybook/releases/tag/v10.6.3)
- [TypeScript 7 and the compatibility API package](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)
- [Circuits UART 1.7](https://github.com/elixir-circuits/circuits_uart/blob/v1.7.0/CHANGELOG.md)
- [Exqlite releases](https://github.com/elixir-sqlite/exqlite/blob/main/CHANGELOG.md)
- [Nx 1.0](https://github.com/elixir-nx/nx/blob/v1.0.0/nx/CHANGELOG.md)
- [Explorer 0.13](https://github.com/elixir-nx/explorer/blob/v0.13.0/CHANGELOG.md)

## Qualification

The qualified code inputs match commit `f721a8e3876f355190bdb3c30817dbb8cce28285` under
`packages/` and `tooling/`. Checks ran on the current lane: Elixir 1.20.2,
OTP 29.0.4 and Rust 1.97.1, with the Java and Python prerequisites described
above. All commands start at the repository root.

| Command | Executed result |
| --- | --- |
| `mix check --base 38c35833` | Passed: root compilation, formatting, lint, 438 tests, catalogue, 567 Markdown files and boundaries; all twenty packages' full gates; 4,420 primary package tests, doctests and properties. The full gates also run native suites, Dialyzer, documentation, audits and archive checks. |
| `pnpm --dir packages/wotex-lab/hosts/workbench run check` | Passed: 153 Workbench and two Storybook-host Biome files; 145 AST files, zero violations; zero Svelte/TypeScript errors or warnings; 61 unit/gate tests; production build and asset budgets. Repeated successfully by the full Lab gate. |
| `pnpm --dir packages/wotex-lab/hosts/workbench run storybook:build` | Passed: all 72 stories build with Storybook 10.6.3. Repeated successfully by the full Lab gate. |
| `WOTEX_LAB_E2E=1 mix pkg wotex-lab cmd --cd hosts/workbench mix test test/e2e` | Passed: 30 Elixir browser tests, including 144 accessibility scans across 72 stories in both themes. |

The Lab gate passes all three reference hosts: 289 Workbench tests, four
Storybook-host tests and one Nerves host test. Matter's fresh normal and
sanitizer builds pass their fixtures and verify the 404-log receipt; all 63
SDK and 18 SDK-free translation units pass clang-tidy. OPC UA passes its 207
native tests. Primary package counts exclude the separately reported archive,
host and native checks.

The minimum toolchain and opt-in software, live-service, formal, interop,
firmware-image and distribution profiles were not rerun. Published inline
reader support remains blocked as described above. This review does not renew
historical conformance or artifact-adoption evidence or claim a release.
