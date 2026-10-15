# WBM.04 — Exact JSON payload projection

Version: 0.1.1. Updated: 2026-10-15. Status: accepted optional target.
Implementation: pure projection and structural selector export implemented.
Evidence: 31 independent vectors, public API/regression and explicit WPF integration checks below.
Owner: wotex_binding_mqtt; requires WBM.01 and wotex_runtime WRT.06 exact JSON decoder.

## Result and ownership

`Wotex.Binding.MQTT.JSONProjection` selects one exact inert C02 value from an
explicit MQTT Delivery and a closed data selector. It is a pure optional path
beside the existing Runtime transport's native JSON result. It changes no old
Transport callback, Delivery shape, Form term, default or JSON convenience API.
It starts no connection, task, process or application and has no client dependency.

The consumer owns broker/connection custody, allowed Topic Names, subscriptions,
credentials, actual receive time, publisher identity, sequence, source generation,
continuity, semantic/profile registration, normalization and authority. A matching
Topic Name, successful decode, QoS or retained flag cannot establish any of those.
A model/profile cannot select a broker, endpoint, credential or code through this API.

## Closed inputs and output

**JP-01.** Public functions are `selector_schema/0`, `validate_selector/1` and
`project/2`. The first returns the WPF-compatible structural DataSchema below;
the second returns `:ok` or a fixed binding error after all semantic checks.
The schema does not express UTF-8 byte ceilings or MQTT wildcard rules: consumers
must run `validate_selector/1` for the installed selector before live use.

Selector is an ordinary non-struct map with exactly `topic` and `path`.
Topic is an exact MQTT Topic Name, valid UTF-8, 1–1024 bytes, without null or
wildcards. No Topic Filter, URI, percent decoding, prefix matching, Unicode
normalization or shared subscription expansion occurs. Path is a proper list
of 0–7 UTF-8 strings, each 0–128 bytes. Empty path selects the complete JSON
value. Segments are already decoded names, not JSON Pointer strings: `a/b`,
`~1`, empty strings and numeric-looking names are literal object keys.
There is no dot syntax, expression, wildcard, default or executable selector.

```json
{"additionalProperties":false,"properties":{"path":{"items":{"maxLength":128,"minLength":0,"type":"string"},"maxItems":7,"minItems":0,"type":"array"},"topic":{"maxLength":1024,"minLength":1,"type":"string"}},"required":["path","topic"],"type":"object"}
```

`project(delivery, selector)` requires the exact ordinary `Delivery` struct:
its four fields must reconstruct identically through public `Delivery.new/2`,
without extra fields, coercion or invalid payload/topic/QoS/retained values.
Payload must be a binary of at most 65536 bytes. Delivery's actual Topic Name
retains WBM.01's 65535-byte MQTT ceiling. Selector validation comes first, then
Delivery reconstruction/payload ceiling, then exact Topic Name comparison.
A different topic returns `:ignore` without JSON parsing or path traversal.
Oversized input still refuses before ignore. An empty matching payload fails JSON.

## Projection and bounded evaluation

**JP-02.** Decode the complete matching payload through the public
`Wotex.Runtime.Codec.JSON.decode/1` implemented at source `0caed876`. Its owned
[exact JSON specification](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-runtime/specs/WRT.06-json-values-v1.md)
owns syntax, decoded duplicate names, integer/decimal types and all input, token,
text, key, depth, node, collection and canonical output limits. In particular,
64-bit integers and decimal coefficients never pass through native floats.
Do not decode through the existing native-number MQTT JSON convenience API.
Malformed or oversized unselected content refuses the complete payload; no partial
parser, selected-field-only bypass or default value is permitted.

Evaluate path segments sequentially on the decoded C02 tree:

- Object: find the unique entry with exactly equal decoded UTF-8 key bytes.
- List: segment must be canonical unsigned decimal (`0` or nonzero digit followed
  by digits), index 0–255 and within the actual list. Leading zero, sign, fraction,
  exponent and `-` do not name an element. Check at most three digits before any
  integer conversion; an arbitrarily long numeric object key is never parsed.
- Scalar, missing object key or missing list element: refuse profile_value_missing.

All seven JSON kinds are selectable, including null, false, empty text and empty
containers; missing remains an error. No conversion, schema interpretation, quality,
unit or source metadata is inferred. Traversal costs at most seven scans of an
already bounded collection (at most 256 members each); it allocates no new tree.
Success is exactly `{:ok, value, %{topic: topic, qos: qos, retained: boolean}}`.
Value is the original selected C02 subtree and still passes `Value.validate/1`.
Metadata preserves exactly the validated delivery fields; it carries no timestamp,
sequence, continuity, authenticated principal, endpoint or profile authority.

## Errors, continuation and compatibility

**JP-03.** Refusals use existing `%Wotex.Binding.MQTT.Error{}` with empty details
and fixed messages containing no input, topic, path, native exception or partial
value. Errors have these exact code/phase/class triples:

| Cause | Code | Phase | Class |
| --- | --- | --- | --- |
| Invalid selector, including native/byte/path bounds | invalid_profile_selector | mapping | permanent |
| Forged/malformed Delivery or native payload | invalid_delivery | client | protocol |
| Payload over 65536 bytes, even on another topic | json_output_limit | codec | protocol |
| Runtime JSON invalid_input | json_invalid_input | codec | protocol |
| Runtime JSON unsupported_value | json_unsupported_value | codec | protocol |
| Runtime JSON output_limit | json_output_limit | codec | protocol |
| Unresolved path | profile_value_missing | mapping | protocol |

Runtime JSON decode/1 has no unsupported_format outcome. No public function
raises for malformed native input. Calls are deterministic and stateless; no
cache, process dictionary, current environment, clock, retry or fallback exists.
An identical call returns the identical outcome. Dropping/duplicating a delivery
or re-running projection never creates a new actual receipt or changes freshness.

**JP-04.** WPF consumers explicitly construct and validate their installed
Binding using this `selector_schema/0`, their exact raw_value_schema and an
immutable qualified raw-value contract reference. This module does not construct
a Binding, choose semantic data, load references or declare all schema types
supported. Consumer registration qualification must bind this projection's exact
version and success/refusal vectors. The actual source owner separately restricts
allowed topics before publishing or admitting a profile. Existing retained
transport results keep their native-number representation and old wire behavior.

## Entry and acceptance

Freeze complete literal payload/selector/expected C02/metadata and refusal rows
in `test/support/json_projection_vectors.json` before code. The standalone Python
checker uses its own exact JSON/Decimal parsing and C02 conversion; it imports
no BEAM or producer encoder. Test code compares literal results through public
APIs. A passing constructor or selected-field match cannot qualify a network source.

| Case | Requirements | Stimulus and falsifier | Level |
| --- | --- | --- | --- |
| JP-T1 | 01/02 | Every kind; multiple channels; object/list paths; slash/tilde/numeric keys; full integers and decimal beyond binary64; frozen exact values/metadata. Rounding, missing=null or changed retained/QoS fails. | Independent software vectors |
| JP-T2 | 01/03 | Unknown/struct/improper/wrong selector; topic/path/key/UTF-8 limits; forged Delivery/extra fields/coerced QoS; exact/one-over payload; unrelated topic with malformed JSON; malformed unselected content. Exception, leak or parsing unrelated payload fails. | Public API |
| JP-T3 | 02/03 | Root and depth-7 path; index 0/255/256, leading zero/sign/long numeric path; duplicate keys; JSON decoder refusal parity; repeated/cross-process projection. Changed representation, float, unbounded index conversion or old-transport regression fails. | Software/regression |
| JP-T4 | 01/04 | Explicit installed WPF Binding and multi-channel profile; validate selector structurally and semantically, compile through actual WPF public API and interpret actual projected reports. Wrong decoded/raw contract or accepted implicit route fails. | Producer integration |

Native-memory measurement, live broker/client custody, physical
source authenticity, host receive clocks and hardware qualification remain
separate consumer/protocol obligations. Full quality gates are milestone evidence.

## Executed software evidence

Contract and 31 literal projection vectors were frozen before code in source
`37ce7aad`. Implementation source is commit
`1188c8f42c1baf35b531de5897d833822fbe204f`; its module is
`packages/wotex-binding-mqtt/lib/wotex/binding/mqtt/json_projection.ex`; ordinary
public API cases are in `test/wotex/binding/mqtt/json_projection_test.exs` under
that package. The explicit integration fixture is
`test/support/json_projection_profiles.exs`, using producer-owned synthetic WPF
vectors. It adds no production or test dependency on Profiles to this package.

On 2026-10-15 with the repository-pinned Elixir 1.20.2 / OTP 29.0.4 and explicit
sibling development sources:

- `python3 packages/wotex-binding-mqtt/test/support/json_projection_oracle.py --check`:
  31 independent records verified against the frozen file.
- `mix pkg wotex-binding-mqtt test test/wotex/binding/mqtt/json_projection_test.exs
  test/wotex/binding/mqtt/delivery_test.exs test/wotex/binding/mqtt/transport_test.exs
  test/wotex/binding/mqtt/library_contract_test.exs`: 28 passed, including one
  executable documentation example. JP-T1–T3 cover exact values/metadata, complete
  refusal categories, closed/forged native inputs, equality/one-over bounds,
  canonical indices, whole-payload validation, distinct missing/null, concurrency
  and unchanged transport/passive-load cases.
- The explicit JP-T4 lane below: three tests passed. One installed Binding feeds
  two actual compiled channels through public Compiler/Projection/Interpreter;
  retained provenance stays retained. Wrong raw type, changed binding identity,
  absent installed raw contract and malformed structural selector refuse.
- Package `compile --warnings-as-errors`, `format --check-formatted`,
  `credo --strict` and `docs --warnings-as-errors`: passed.
  `mix wotex.boundary --package wotex-binding-mqtt`: no sibling findings.
  `elixir packages/wotex-binding-mqtt/bin/check_boundary.exs
  packages/wotex-binding-mqtt`: package source boundary passed.
- `mix docs.check`: all 514 tracked Markdown links resolve and the generated
  family catalogue is current. Both worktree and staged `git diff --check` pass.

Reproduce JP-T4 from the repository root after the ordinary focused test build:

```sh
mise exec -- mix pkg wotex-profiles compile --warnings-as-errors
mise exec -- elixir \
  -pa 'packages/wotex-binding-mqtt/_build/test/lib/*/ebin' \
  -pa packages/wotex-profiles/_build/dev/lib/wotex_profiles/ebin \
  packages/wotex-binding-mqtt/test/support/json_projection_profiles.exs \
  packages/wotex-profiles/priv/vectors
```

These are live-source software checks, not exact-archive/registry installation,
a client/broker interoperability claim or a host publisher. Full-suite, coverage,
Dialyzer, archive and minimum-toolchain gates remain milestone obligations.

## Sources and interpretations

- [RFC 8259 (December 2017)](https://www.rfc-editor.org/rfc/rfc8259): JSON grammar;
  exact representation/bounds are the Runtime-owned package interpretation.
- [RFC 6901 (April 2013), section 4](https://www.rfc-editor.org/rfc/rfc6901):
  contextual object/list lookup and canonical indices. This API uses already
  decoded string segments and does not claim JSON Pointer string/URI support.
- WBM.01 owns MQTT Delivery/Topic Name/QoS, and WPF.02 owns explicit registrations
  and interpretation. No new MQTT or W3C protocol conformance claim is made.
