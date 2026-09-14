# WCT-C01 executable contract map

This document maps the public WCT.01, WCT.02, and WCT.03 value contracts to
executable evidence. It is a verification index, not a fourth normative
specification. The three documents under `specs/` remain the owners of field
meaning and compatibility.

The data matrix in
`test/wotex_continuum/contract_inventory_test.exs` is checked against every
registered struct. Adding a field without classifying it as required or
optional therefore fails the test. The same test exercises `from_map/1`, its
`new/1` alias, the `WotexContinuum` facade, forged-struct reconstruction, and
encoding where each route applies.

## Envelope and null rules

Encoded top-level values require explicit `kind` and `schema_version` members.
`Codec.decode/2` rejects either omission at its exact JSON Pointer. A
module-specific constructor may receive a native map without those two members;
it supplies the module's registered kind and current schema version. An
explicit wrong value is never replaced.

Optional means absent, not `null`. Absence selects the default listed below.
Explicit `null` is admitted only as a JSON value: WCT.02 `input`, `value`, or a
present successful `output`, and nested failure `details`. Typed strings,
integers, timestamps, objects, arrays, and nested contracts reject `null` at
their member path. `action_result.output_present?` is an internal marker used
to retain the distinction between an absent output and a present JSON `null`;
it is not a wire member.

## Registered kinds and fields

| Owner and kind | Required payload members | Optional members, omission default, and conditional rule |
| --- | --- | --- |
| WCT.01 `continuum_manifest` | `manifest_id`, `artifact`, `compatibility`, `supported_modes`, `capabilities` | `extensions` -> `{}`. Artifact, capability ID, and mode relationships are checked after nested construction. |
| WCT.01 `compatibility` | `schema_requirement` | `required_capabilities` -> `[]`; `extensions` -> `{}`. Requirement IDs must be unique. |
| WCT.01 `execution_scope` | `execution_id`, `node_id`, `mode`, `observed_at` | `extensions` -> `{}`. Nested mode is reconstructed. |
| WCT.01 `capability` | `id`, `version`, `operations`, `modes`, `network`, `degradation` | `extensions` -> `{}`. Operations and modes are unique; modes are non-empty. |
| WCT.02 `observation_proposal` | `proposal_id`, `thing_id`, `affordance_type`, `affordance_name`, `value`, `observed_at`, `context` | `sequence` -> absent/`nil`; `quality` -> `{}`; `evidence` -> `[]`; `extensions` -> `{}`. A present `value` may be JSON `null`. |
| WCT.02 `action_intent` | `intent_id`, `thing_id`, `action_name`, `input`, `requested_at`, `idempotency_key`, `context` | `requested_by` -> absent/`nil`; `evidence` -> `[]`; `extensions` -> `{}`. A present `input` may be JSON `null`. |
| WCT.02 `action_result` | `result_id`, `intent_id`, `status`, `context` | `output`, `error`, `started_at`, `completed_at` -> absent/`nil`; `evidence` -> `[]`; `extensions` -> `{}`. `succeeded` requires present output (including JSON `null`) and completion; `failed` requires failure and completion; `cancelled` requires completion; non-terminal states exclude all terminal fields. Completion cannot precede start. |
| WCT.02 `evidence_reference` | `evidence_id`, `uri`, `digest`, `media_type`, `captured_at` | `extensions` -> `{}`. The digest is structural identity only; no bytes are fetched. |
| WCT.02 `delivery` | `delivery_id`, `item_kind`, `item_id`, `source`, `destination`, `status`, `attempt`, `emitted_at` | `sequence`, `acknowledged_at`, `error` -> absent/`nil`; `extensions` -> `{}`. `acknowledged` requires its time; `failed` requires failure; other states exclude both. Acknowledgement cannot precede emission. |
| WCT.03 `mode` | `deployment`, `connectivity` | `extensions` -> `{}`. `air_gapped` requires `disconnected`. |
| WCT.03 `lifecycle` | `subject_id`, `state`, `generation`, `changed_at` | `reason` -> absent/`nil`; `extensions` -> `{}`. Transition options follow the same absent-versus-null rule. |
| WCT.03 `degradation` | `degradation_id`, `subject_id`, `level`, `capabilities`, `reason_codes`, `since`, `recoverable` | `evidence` -> `[]`; `extensions` -> `{}`. `none` requires empty detail lists; other levels require non-empty lists. |
| WCT.03 `exit_receipt` | `receipt_id`, `subject_id`, `operation`, `status`, `requested_at` | `completed_at`, `error` -> absent/`nil`; `artifacts`, `residuals` -> `[]`; `extensions` -> `{}`. Terminal states require completion; `failed` requires failure; `partial` requires residuals; completed removal excludes residuals. |

Nested value coverage is part of the same executable matrix:

| Nested value | Required members | Optional/default/null rule |
| --- | --- | --- |
| `Artifact` | `name`, `version`, `digest` | No optional members. |
| `CapabilityRequirement` | `id`, `version_requirement` | No optional members. |
| `Failure` | `code`, `message` | `details` -> `{}`; explicit JSON `null` is retained. |

Every registered kind has a valid vector and an exact canonical-byte vector.
`contract_inventory_test.exs` supplies per-field invalid, default, null,
unknown-field, and forged-struct evidence for all 13 kinds and the three nested
values. `vector_test.exs` proves repeatable canonical round trips and exact
invalid-vector errors. `schema_conformance_test.exs` separately records the
documented JSON Schema subset; full schema agreement remains WCT-C03.

## Error evidence index

Consumers match `code`, `phase`, and `path`, never message prose. These test
groups exercise the public error surface:

| Error family | Codes and conditions | Executable evidence |
| --- | --- | --- |
| Closed fields and reconstruction | `required`, `unknown_field`, `duplicate_field`, `invalid_key`, `invalid_type`, `unsupported_value` | `contract_inventory_test.exs`, `validation_test.exs`, `codec_test.exs` |
| Scalar and collection validation | `too_short`, `too_long`, `invalid_utf8`, `invalid_iri`, `invalid_digest`, `invalid_version`, `invalid_version_requirement`, `invalid_timestamp`, `invalid_enum`, `invalid_integer`, `invalid_number`, `invalid_json_value`, `duplicate_value` | `validation_test.exs`, `property_contract_test.exs`, `codec_test.exs` |
| Envelope and registry | `wrong_kind`, `unknown_kind`, `unsupported_schema_version`, missing discriminator/version | `contract_inventory_test.exs`, `codec_test.exs`, invalid vectors |
| Cross-field state | `invalid_mode`, `invalid_result_state`, `invalid_delivery_state`, `invalid_degradation_state`, `invalid_exit_state`, `invalid_time_order`, `unsupported_capability_mode` | `lifecycle_test.exs`, `value_state_test.exs`, invalid vectors |
| Lifecycle graph and options | `invalid_transition`, `invalid_time_order`, `invalid_options`, `unknown_field` | `lifecycle_test.exs` |
| Decode, encode, and bounds | `invalid_json`, translated decode errors, `limit_exceeded`, `invalid_limit`, `invalid_options`, canonical JSON rejection | `codec_test.exs`, `property_contract_test.exs`, `validation_test.exs` |
| Embedded schema and supplied Thing Description | `unknown_schema`, `thing_id_required`, `thing_id_mismatch`, `invalid_thing_description` | `library_contract_test.exs`, `thing_reference_test.exs` |

## Exact lifecycle transition matrix

`lifecycle_test.exs` executes all 49 ordered state pairs. It accepts exactly:

```text
staged -> ready | removed
ready -> active | stopped | removed
active -> degraded | draining | stopped
degraded -> active | draining | stopped
draining -> stopped
stopped -> ready | removed
removed -> (none)
```

For every accepted edge it proves a one-step generation increment, retained
extensions, caller-supplied reason handling, and acceptance of an equal
timestamp. Every other edge returns `invalid_transition` at `/state`; an
otherwise allowed edge with an earlier time returns `invalid_time_order` at
`/changed_at`.

## Deliberate boundary

This evidence constructs, validates, compares, transitions, and encodes inert
values only. It adds no process, persistence, trusted clock, identity,
authorization, provider selection, dispatch, retry, or effect claim. Native
UTF-8 parity beyond the covered paths and native-versus-decoder resource-bound
parity remain the explicit WCT-C02 work; full JSON Schema vocabulary agreement
remains WCT-C03.
