# Generic protocol, profile-reader and streaming delivery

Version: 1.1.0. Updated: 2026-10-16. Status: accepted build order.
Implementation: bounded WPF reader/compiler/authoring APIs are implemented;
stream mechanisms and wider consumer/installed qualification remain planned.
The owning catalogues retain exact implementation and software-evidence scope.

## Outcome and prerequisites

Support independently supplied sensor/device definitions through installed
protocol mechanics without growing a device-model catalogue inside WoTEx.
Ordinary protocol clients remain usable without profile interpretation, routines
or streaming. The [allocation decision](profile-and-stream-boundary.md) owns
scope; WPF.01–03 and WST.01–02 own the new concrete producer targets.

`wotex_profiles` is the registered twentieth package in `tooling/packages.yaml`
and the generated family catalogue. `wotex_streams` remains a documentation-only
target outside that graph. This plan adds no dependency, SDK or runtime registry;
its stages retain the distinction between existing WPF APIs and remaining joins.

| Stage | Work and dependency | Exit obligation |
| --- | --- | --- |
| GP0 allocation | Review all producer/consumer profile, routine and media references against the decision | One owner for protocol, reader, external definitions, component processing and consumer authority; no worldwide model catalogue |
| GP1 reader values | WPF.01 schemas, pure Profile/Registry/Definition/Limits and exact unit descriptors | Unknown quantity IDs admitted as inert supplied descriptors; no hard-coded sensor enum, remote fetch or implicit identity |
| GP2 interpretation | WPF.02 compiler/projection and explicit installed selector/codec ports | Independent conversion/null/quality vectors, selected closure only, bounded work and deterministic output |
| GP2A authoring tools | WPF.03 exact installed-contract export, draft finalizer, shared diagnostics/CLI | Schema/semantic/check parity, hash/DAG oracle, bounded report/step counters; no provider or model catalogue |
| GP3 industrial counterexample | Public Modbus/OPC UA or supported SDK adapter plus external multi-channel definitions | Previously unseen pressure/model data works without editing reader; register/quality/timestamp semantics preserved; no physical claim from peer |
| GP4 second consumer | Another independent archive consumer and WRO.05 bridge | Same interpretation without shared private state; v1 routines reject unsupported dimensions/shapes rather than coerce |
| GP5 consumer authoring/delivery | Consumer-local templates, private draft/source custody, manual review/import; optional bounded generation after manual path | Exact immutable closure/basis, independent fixture evidence, stale/repair/authority/mode failures; no shared repo or automatic activation |
| GP6 stream values | WST.01 public stream descriptor/frame/status/port schemas and scripted peers | Bounded framing/credit/lifecycle, discontinuity and truthful timing; no media processing required |
| GP7 first protocols | WST.02 allocation: qualify each selected Sendspin/RTSP/RTP or other profile under its own exact contract | Independent protocol peers and security/clock/loss tests; no conversion between unrelated protocols by name |
| GP8 media component join | Independently selected playback/capture or surveillance component uses stream ports | Protocol evidence separate from decode/render/inference evidence; source consent and application state remain consumer-owned |
| GP9 delivery milestone | Archive, passive load, public boundaries, docs/native checks of changed owners | Current claimed cells have exact artifacts/results; no unrelated all-package or Dialyzer sweep |

GP3 does not require physical hardware to establish the reader seam; actual
device/cohort qualification is a separate consumer gate. Existing legacy
admission stays narrow until the new consumer join passes. Focused mechanism
checks accompany each stage; full changed-package/native gates run at stable
milestones. Benchmarks require an explicit workload/invocation, not guessed
throughput from the number of supported profiles.

## Language and dependency allocation

Core, reader values and interaction adapters use Elixir/OTP public ports.
A selected protocol may use C/C++/Rust/native SDK processes under its own
custody. Generic stream delivery does not require FFmpeg, GStreamer, a DSP
engine, Core Audio, an NVR or a streaming-service account. A consumer component
may select those independently. Exact versions/source/notice inventories are
entry artifacts of each implemented profile, not inferred from research.

Consumer-owned profiles supply data, compatible notices, semantic identities
and test vectors. Public templates ship in consumer releases; private drafts
remain private. Optional exported bundles are explicitly imported and locally
reviewed. No automatic download or trusted-code compilation is introduced.
An installed binding registration owns its selector grammar and supported
operations; data cannot resolve an arbitrary module or native executable.

## Review record and continuation

Walk: unseen scalar sensor -> external definition/profile -> pure projection ->
consumer-qualified observation -> explicit application decision. Adverse walk:
changed firmware/definition while a command is pending -> stale basis -> refused
unsent work/unknown handed-off outcome, never automatic retry or wider capability.

Walk: camera/source -> negotiated stream -> bounded packet delivery -> selected
decoder/recorder/display. Adverse walk: packet loss/clock step/takeover -> gap and
new epoch or retirement -> consumer sees uncertainty; packet timestamps cannot
prove a rendered image or synchronized speaker.

These are reviewed design traces, not execution. A code-discovered gap revises
the owning contract/catalogue before support or privilege is broadened.

Authoring walk: consumer's installed contract + permitted source passages ->
manual/AI draft -> mechanical finalization -> shared semantic/binding validation
and independent fixtures -> consumer review -> separate current admission.
Adverse walk: schema-valid wrong mapping or binding change during review ->
incompatible/unresolved/stale refusal; no confidence override or active change.
The [research decision](consumer-profile-authoring-research.md) records the
primary sources and rejected mandatory-catalogue/provider allocations.
