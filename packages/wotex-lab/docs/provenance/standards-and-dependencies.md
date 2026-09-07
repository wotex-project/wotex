# Source and dependency baseline

Observation date: 2026-09-07. The companion `source-index.json` is a checked-in
inspection snapshot, not a generated release ecosystem manifest or a progress
tracker. It records immutable repository revisions, catalogue/plan paths,
observed source statuses and exact public behaviour source locations. All
eight inspected WoTEx worktrees were clean. No private implementation or local
filesystem path is a published input.

That original revision snapshot remains historical. The follow-up
[seam review](consumer-seam-review.md) describes scoped source repairs and the
separate content-based cohort, which includes uncommitted input. It does not
rewrite the original snapshot as though repairs existed at those commits.
The [workbench/observability decision](../decisions/0003-native-workbench-and-observability.md)
records the additional primary references and dependency boundaries.

The WoTEx Hex API routes for `wotex`, `wotex_runtime`, `wotex_binding_http`,
`wotex_binding_mqtt`, `wotex_directory`, `wotex_continuum`, `wotex_conformance`
and `wotex_nx` returned HTTP 404 at inspection. This is a dated observation,
not a permanent assertion. Candidate metadata uses 0.1.0 source baselines;
archive digests are not invented. `ex_maude` was available as 0.4.1.

## Primary references

| Source | Selected use and limitation |
| --- | --- |
| [W3C TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/) | Core owns supported TD/TM/DataSchema meaning; no new Lab conformance claim |
| [Nx 0.13.1](https://hexdocs.pm/nx/0.13.1/Nx.html) and [Serving](https://hexdocs.pm/nx/0.13.1/Nx.Serving.html) | Explicit tensor/backend/defn/batch execution; Serving names/options follow this cohort |
| [Axon 0.8.1](https://hexdocs.pm/axon/0.8.1/Axon.html) | Consumer training/serving integration contract; integration dependency cohort requires validation |
| [Req](https://hexdocs.pm/req/Req.html) | Chosen finite HTTP and streaming reference; SSE lifecycle remains explicit Lab work |
| [EMQTT 1.16.0](https://hex.pm/packages/emqtt/1.16.0) | Chosen MQTT 5 client behind the optional `{:emqtt, "~> 1.15"}` requirement, resolved to 1.16.0 by `mix.lock`; credential custody and no-automatic-reconnect are asserted against this revision, and wire/session behaviour beyond the exercised cases is not claimed |
| [eclipse-mosquitto 2](https://hub.docker.com/_/eclipse-mosquitto) | Disposable local MQTT broker for the WLB.04 broker lane, selected by tag; not a digest-pinned release artifact and not a broker conformance claim |
| [Exqlite](https://hexdocs.pm/exqlite/Exqlite.html) | Chosen SQLite access; transactions/conflicts belong to independent Lab adapter |
| [ExMaude 0.4.1 source](https://github.com/futhr/ex_maude/tree/9bc259ff0d1ea3153c20e7f7f439827c1d4ba3d4) | Explicit pools/public search and model-scoped evidence; binary separately provisioned |
| [Maude](https://maude.cs.illinois.edu/) | Rewriting logic engine; finite-model claims and executable license are separate from WoT standards |
| [Livebook](https://livebook.dev/) and [Nerves Livebook](https://github.com/livebook-dev/nerves_livebook) | Executable notebooks and bootable embedded adoption convention; Lab supplies its own tested artifacts |
| [ExDoc 0.40.4](https://hexdocs.pm/ex_doc/0.40.4/readme.html) | Markdown/llms documentation inputs, not a replacement for normative catalogues |
| [OpenAPI 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) | Selected Lab HTTP description dialect; no claim about all generators supporting it |
| [AsyncAPI 3.1.0](https://www.asyncapi.com/docs/reference/specification/v3.1.0) | Selected event/MQTT interface description dialect |
| [JSON-LD 1.1](https://www.w3.org/TR/json-ld11/) and [RDF 1.1 Turtle](https://www.w3.org/TR/turtle/) | Ecosystem graph representations only |
| [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Pinned stdio/Streamable HTTP baseline; transport conformance and control policy require separate tests |

## Acknowledged advisories in the optional MQTT cohort

Observation date: 2026-09-08. The optional `emqtt` requirement resolves `gun`
and `cowlib`, which carry open advisories with no patched Hex release at that
date: `GHSA-w4f7-4cxr-rv3c` (gun), `EEF-CVE-2026-43966`, `EEF-CVE-2026-43969`
and `EEF-CVE-2026-43971` (cowlib). Every affected code path is Cowboy/Gun HTTP,
cookie, link-header or HPACK/QPACK handling reached through emqtt's WebSocket
and QUIC transports. `Wotex.Lab.Adapters.MQTT.Session` selects `emqtt_sock`,
the plain TCP transport, and never `emqtt_ws` or `emqtt_quic`.

`mix.exs` (`hex: [ignore_advisories: ...]`) and `.mix_audit.ignore` therefore
acknowledge exactly these identifiers so `mix check` reports a real regression
rather than a permanent failure. This is a dated, scoped acknowledgement, not a
claim that the advisories are invalid: a consumer that also uses gun or cowlib
for HTTP is affected independently of Lab, and the acknowledgement must be
removed once a patched release exists.

Selected versions are design baselines, not claims that they are universally
the newest or compatible. Runtime dependencies are pinned by `mix.lock`; full
profile dependency and binary cohorts are admitted by WLB.08. Changing a source
revision requires checking its spec/API/claim differences and renewing affected
evidence. External standards schemas are linked, not copied into Lab fixtures.
