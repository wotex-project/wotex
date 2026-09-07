# Wotex completion contract

Plan version: 1.0.0. Package baseline: 0.1.0. Normative owners:
[specification catalogue](../specs/catalogue.yaml).

This is a versioned implementation and acceptance baseline, not a progress log.
An accepted baseline is immutable in meaning: a changed obligation needs an
explicit new plan version and compatibility review. Execution status, attempts,
machine-local evidence and handoffs belong only in ignored
`docs/tasks/local/wotex-tracker.yaml`. Package inputs allowlist publishable
documentation and structurally exclude `docs/tasks/local/`; archive inspection
must continue to prove that boundary whenever package inputs change.
The catalogue's `implementation_status` describes source coverage of a spec,
not a passed release gate. No checkbox, green build or package version implies
W3C certification, complete standards conformance or stable API admission.

## Package boundary

Wotex owns the immutable Elixir value boundary for Thing Description 1.1,
Thing Model 1.1, DataSchema, Form, Property, Action, Event and security-scheme
definitions. It owns bounded JSON admission, documented semantic checks,
extension preservation, structured errors, provenance and deterministic
package-local serialization.

The consumer owns canonical Thing state, identifier allocation, credentials,
authentication, policy, endpoint selection, protocol execution, persistence,
discovery, supervision, retries and proof of physical effects. No database,
application callback, hidden worker, global registry, credential provider,
remote-context fetcher or automatic model instantiation belongs in this package.
Consumer vocabulary inherits the W3C meanings exposed here; consumer extensions
remain extensions, not new meanings for standard terms.

## Exact public seam

| Surface | Contract and executable owner |
| --- | --- |
| `Wotex.td_context_1_1/0`, `td_media_type/0`, `tm_media_type/0` | Exact context and media-type constants; `library_contract_test.exs` and aggregate tests. |
| `Wotex.ThingDescription` | `parse/2`, explicit raising `parse!/2`, `from_map/2`, `to_map/1`, `validate/2`, `id/1`, `put_id/3`, `encode/2`, `schema_info/0`; WTX.01. |
| `Wotex.ThingModel` | Same operation family, distinct aggregate; WTX.04. No TD instantiation or remote `tm:ref` resolution. |
| Six value modules in WTX.02 | `new/2`, `to_map/1`; Form also `href/1`, `operations/1`; SecurityScheme also `scheme/1`. Context-specific Form validation is a value check, not execution. |
| `Wotex.Error` | Match `code`, `phase`, `path`; `message` is explanatory, `details` is diagnostic. Ordinary admission returns `{:ok, value}` or `{:error, error_or_nonempty_error_list}`. Accessors require their documented typed input. |

All test names above are relative to `test/wotex/`. Internal validator and JSON
modules support these surfaces; their implementation visibility is not permission
to advertise a second independently stable public API.

`parse/2` accepts binary JSON and enforces a byte limit before decoding;
map admission enforces native JSON values, depth and node limits. Defaults are
1,048,576 source bytes, 64 nested containers and 100,000 nodes. Positive keyword
limit values override defaults; existing invalid limit values fall back to
defaults. Malformed option containers are not currently a documented total
input surface. `validate: false` skips aggregate schema/semantic validation,
not JSON admission, and is never a conformance result.

Only untouched parsed values support source-byte return. `put_id/3` invalidates
that representation. Canonical encoding sorts keys; it does not establish
RFC 8785 JCS, a signature format or equivalence across future encoder versions.
Unknown JSON extension values survive without interpretation. Security-reference
existence is validated; secrets, trusted issuers and authorization are not.

## Concurrency, lifecycle, recovery and security

Operations run synchronously in the caller. Concurrent consumers share immutable
values, not mutable state; there is no serialization queue or worker lifecycle.
Stopping the consumer requires no library drain callback. Recovery consists of
reloading consumer-owned bytes and validating them under a selected package
version; the library provides neither durable checkpoints nor automatic replay.
No operation proves that an Action occurred.

JSON input, Form URIs, security definitions and extensions are untrusted. Remote
JSON-LD contexts are never fetched. The consumer must keep credentials out of
public examples and logs; parsing preserves supplied values and is not a secret
redactor. Review error details separately before claiming they are universally
safe to log. Byte bounds do not constitute a CPU or peak-memory benchmark:
depth/node checks follow decoding, and bounded source can still amplify memory.

## Standards-claim matrix

Baseline: [TD 1.1 Recommendation, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/).
The informative schema revision and digests are owned by
`docs/provenance/w3c-td-schema-1.1.md` and
`docs/provenance/w3c-tm-schema-1.1.md`, not by a moving upstream branch.

| Claim | Value | Operation | Interoperability | Profile | Certification |
| --- | --- | --- | --- | --- | --- |
| TD 1.1 JSON | WTX.01 documented schema and semantic subset | Parse, validate, encode | Local round trips proven by tests; independent implementation exchange requires WTX-C04 | No WoT Profile claim | None |
| Thing Model 1.1 JSON | WTX.04 distinct model value | Parse, validate, encode; no instantiate/resolve | Local vectors only until WTX-C04 | No profile claim | None |
| DataSchema, Forms and affordances | WTX.02 definitions and extension preservation | Constructor/accessor only; no DataSchema instance evaluator or transport | Metadata preservation does not prove binding compatibility | No binding/profile claim | None |
| Package canonical JSON | Project-defined deterministic bytes | Key-sorted serialization | Exact supported encoder cohort only | Not RFC 8785 | None |

Full Recommendation conformance requires requirement-by-requirement evidence;
informative-schema success is not that evidence. TD 2.0 drafts, Scripting API,
protocol bindings, discovery, Turtle/RDF/XML and model instantiation remain
outside this baseline. Implementing them is not necessary to finish this package.

## Independent implementation work

Each work item is a bounded contract and can be implemented from this checkout.
Test additions belong beside the listed package tests, not in coordination hooks.

| ID | Prerequisites | Deliverable | Acceptance |
| --- | --- | --- | --- |
| WTX-C01 | WTX.01–WTX.04 | Requirement-to-test inventory and exact exported API/error catalogue, including raising variants, invalid option fallback and staged validation | Every advertised behavior links to valid, invalid and boundary cases; uncovered claims remain explicit rather than marked complete. |
| WTX-C02 | WTX-C01 | Admission and safety tests for both aggregates and every wrapper | Unicode keys/values, escaped paths, byte/depth/node boundaries, extension preservation, source invalidation and security references pass. Characterize duplicate JSON keys, manually forged structs, malformed option containers and error-detail disclosure; change any accepted behavior only with an explicit compatibility classification. |
| WTX-C03 | WTX-C01 | Archive consumer evidence and package-content inspection | Unpacked package builds without source checkout dependencies; contains both pinned schemas, notices and specs; runs TD/TM parse, wrapper and typed-error examples in an independent minimal Mix consumer. Local trackers and generated audit artifacts are absent. |
| WTX-C04 | WTX-C02, WTX-C03 | Consumer-neutral reference examples and independent standards corpus | Known valid/invalid TD and TM documents exchange with a named, revision-pinned independent implementation or published test corpus. Record exact operations and counterexamples; no transport or profile claims follow from value exchange. |
| WTX-C05 | WTX-C02–WTX-C04 | Versioned compatibility and release dossier | Confirm minimum/current toolchains, exact locked and permitted dependency cohorts, schema/vector/archive digests, licenses, security review and API evolution decisions. Maintainer reviews a candidate; automated work never publishes it. |

Work may progress in parallel after prerequisites, but each source/spec/test
change has one owner. No package requires a central commit log, remote commit per
attempt, worker coordinator or cross-repository scheduler to implement these IDs.

## Acceptance gates

| Gate | Required evidence; never inferred from a preceding gate |
| --- | --- |
| `repository_green` | `mix deps.get --check-locked` and `mix check --no-retry` pass on the exact checkout; warnings-as-errors, strict Credo, tests, >=95% coverage, Doctor, Dialyzer, dependency audits, docs and existing boundary/package checks. Record toolchain and source/lock digest. |
| `archive_consumer_green` | WTX-C03: exact archive builds and public API examples pass in an independent consumer. Existing `bin/check_package.exs` compiles the unpacked source and checks no callback; this alone does not exercise consumer examples. |
| `reference_consumer_green` | WTX-C04: consumer-neutral end-to-end value examples and explicitly scoped independent corpus evidence using the same archive. No unpublished local dependency assumed. |
| `public_release_candidate` | All three preceding gates, content/license/provenance/security review, accurate docs and non-claims; immutable candidate artifact and evidence. This is permission to evaluate, not to push, tag or publish. |
| `stable_api_candidate` | WTX-C05 plus explicit review of every public function/result/error, compatibility policy and negative vectors. Version 0.1.0 and high coverage do not themselves promise stable API semantics. |

Fresh checkout procedure: read `CLAUDE.md`, this plan and the owning WTX files;
run `mix setup`, then `mix check --no-retry`. Use README public examples for the consumer
exercise. Check archive contents before claiming any public candidate. Record
the exact source tree, package version, archive SHA-256, lock digest, schema
digests, vector/test inputs, command results, Elixir/OTP versions and claim
dimensions in local evidence. Dirty-tree proof must name its source-tree digest;
a commit identifier alone cannot identify uncommitted inputs.

## Remaining-claim ledger

| Claim needing evidence or explicit exclusion | Owner | Discharge condition |
| --- | --- | --- |
| Complete Recommendation validation | WTX-C01, WTX-C04 | Requirement map and independent corpus; otherwise retain documented subset. |
| Uniform malformed-input behavior and safe error details | WTX-C02 | Explicit contract plus regression tests for option containers, duplicate keys, forged values and disclosure limits; do not infer totality from ordinary map tests. |
| Predictable resource consumption | WTX-C02 | Adversarial bounded-input measurements and a stated supported envelope; do not describe structural bounds as latency guarantees. |
| Independent install/API usage | WTX-C03 | External minimal consumer exercises both TD and TM, not compile-only archive success. |
| Local execution files excluded from public archives | WTX-C03 | Explicit package exclusions plus a package-content regression; Git ignore alone is insufficient. |
| Cross-implementation value exchange | WTX-C04 | Exact implementation/corpus revision and operation results. |
| Stable public API | WTX-C05 | Explicit stability review; do not silently strengthen the 0.1 contract. |

This ledger fixes the obligations of this plan version. It is not an audit
tracker: completion receipts and remaining execution state stay local.
