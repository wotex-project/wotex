# WNX.01: Observation and numerical boundary

**Specification version**: 1.2.0. **Contract**: Accepted initial public API.
Implementation coverage is indexed in `catalogue.yaml`; acceptance of this
contract does not assert archive, reference-consumer or stable-API readiness.

## Ownership

This package owns immutable Property/Event observation values, feature and
output schemas, deterministic temporal windows, explicit unit conversion,
quality and missing-value policy, normalization, tensor/mask construction,
`Nx.Batch` construction, conversion provenance, and inert typed output values.

The consumer owns canonical Thing state, observation admission, clocks,
identity, model selection and execution, policy, evidence, and Action dispatch.

## Requirements

1. A feature MUST identify an exact Thing and Property or Event affordance,
   W3C DataSchema, dtype, shape, unit, accepted quality, missing policy, and
   normalization rule. Windowing and encoding MUST NOT combine observations
   from different Things that happen to use the same affordance name.
2. Feature order MUST be schema order and MUST NOT depend on map iteration.
3. Observation timestamps and window bounds MUST be caller supplied. Windowing
   MUST use documented deterministic tie-breaking and MUST NOT read a clock.
   Exact ties select the lexically lowest observation identifier. Latest ties
   select the greatest timestamp and then lowest identifier. Nearest ties
   select lowest absolute distance, then earlier timestamp, then lowest
   identifier.
4. Values MUST pass DataSchema type/shape checks before tensor construction.
   Non-finite values MUST be refused unless explicitly allowed by the feature.
   The finite-value policy also applies after normalization and dtype conversion.
   Integer values MUST fit the selected signed or unsigned dtype without wrapping
   or truncation. Floating-point rounding within the selected dtype is permitted;
   arithmetic overflow during normalization MUST return a structured error.
   These rules apply to observations, converted units, and missing-value fills.
   Supported DataSchema constraints compose conjunctively: an `enum` MUST NOT
   bypass a `const` on the same value, including array items and decoded output.
5. Unit mismatch MUST use an explicit conversion port or fail. Unit identity
   MUST never be guessed.
6. Missing or rejected-quality values MUST follow the declared `:error` or fill
   policy and MUST set a mask. Silent coercion is forbidden.
7. Normalization parameters MUST be explicit and validated. The package MUST
   not derive mutable training statistics from input.
8. Encoding MUST produce typed values, validity masks, quality codes,
   deterministic feature slices, provenance, and an `Nx.Batch` without starting
   a process, selecting a backend, or reading a tensor back from a backend.
   Each batch entry is `{values_tuple, masks_tuple, quality_vector}`. Both
   tuples follow feature order; a mask element is `1` where observed and `0`
   where filled; the quality vector uses `good=0`, `uncertain=1`, `bad=2`, and
   `missing=3`. Axis 0 of the stacked batch is the window row of one sample;
   the package MUST document that `Nx.Serving` splits that axis. A row that
   names a feature absent from the schema MUST fail with
   `unknown_row_feature`. Normalization runs in host double precision before
   dtype conversion, so a value normalized in `f32` inside a model and a value
   normalized here can differ by rounding; the package MUST state this and
   MUST NOT claim bitwise train/serve equivalence.
9. Decoding MUST validate output shape and finite-value policy, then return an
   inert observation, prediction, anomaly, or Action proposal. It MUST NOT
   execute or authorize an Action. An anomaly threshold MUST be represented in
   the accepted output dtype before comparison, and its comparison rule MUST be
   explicit.
10. Limits for observations, rows, features, and flattened width MUST be
    explicit and checked before allocation. Decoder input MUST be one
    unvectorized tensor matching the exact accepted output shape and dtype.
11. Public keyword options MUST be well-formed, unique, and limited to the
    options owned by that operation. An observation value MUST be explicitly
    supplied; omitted input and the JSON value `null` are not equivalent.
12. Opaque numerical structs MUST be revalidated at every consuming boundary.
    Struct shape alone MUST NOT bypass feature, observation, row, schema,
    window, or output-schema invariants.

## Closed public inputs and operations

All names below are under `Wotex.Nx`. Constructors and conversion operations
return `{:ok, value}` or `{:error, %Error{}}`; callers MUST NOT infer admission
from struct shape. Unknown or duplicate keyword options are rejected.

| Entry point | Accepted input and defaults | Result / ownership |
| --- | --- | --- |
| `Observation.new/1` | `id`, `thing_id`, `affordance_type` (`:property` or `:event`), `affordance_name`, integer `observed_at`, explicit `value`; optional `unit`, `quality` (default `:good`), `source`, `metadata` (default `%{}`) | Immutable observation, not canonical admission |
| `Feature.new/1` | `name`, exact Thing/affordance identity, core `DataSchema`; optional exact `shape`, compatible `dtype`, `unit`, `accepted_quality` (default good/uncertain), `missing` (default `:error`), `normalization` (default `:none`), `allow_non_finite?` (default false) | Immutable numerical feature; schema-inferred shape/dtype when omitted |
| `Schema.new/1` | Ordered `features`; positive `max_rows` (1024), `max_features` (256), `max_width` (65536), `batch_key` (`:default`) | Nonempty bounded feature contract; feature names unique |
| `Window.new/1` | Integer `start`, positive integer `step` and `count`; `strategy` (`:latest` default, `:exact`, `:nearest`), optional nonnegative `max_age` | Clock-free window in the consumer's common integer time coordinate |
| `Window.resample/3,4` | Observations, Schema, Window; only `max_observations` (10000) and `max_work` (5000000) options | Ordered Rows; admission score is `n + count * features * L(n)`, with `L(n)` defined below |
| `Row.new/2` | Integer timestamp and feature-name-to-observation map | Immutable row; supplied feature values are checked again when encoded |
| `Encoder.encode/2,3` | Nonempty Rows, Schema; only `unit_converter: {module, config}` | Encoded batch, feature order, timestamps, provenance and layout |
| `OutputSchema.new/1` | `kind`, exact Thing/affordance identity, core `DataSchema`; optional shape/dtype, max_width (65536), unit, metadata, finite policy; anomaly threshold/rule only for anomaly | Closed inert-output contract |
| `Decoder.decode/2,3` | One unvectorized tensor, OutputSchema, kind-specific metadata/time options below | Observation, Prediction, Anomaly or ActionProposal; never dispatched |
| `Wotex.Nx.quality_codes/0` | No arguments | Stable mapping from requirement 8 |

`Feature` missing policy is `:error` or `{:fill, scalar}` with a numerical or
boolean scalar, validated against the feature contract. Normalization is `:none`,
`{:z_score, mean, stddev}` with positive stddev, or
`{:min_max, minimum, maximum}` with maximum greater than minimum. No online
statistics or inferred conversion rules are permitted. Shapes MUST equal the
shape inferred from the accepted numerical DataSchema; an explicit shape is not
permission to reshape arbitrary data. Unit defaults come from the DataSchema.

Decoder options common to all kinds are `id` and `metadata`. Observation adds
`observed_at`, `quality`, `source`; prediction adds `produced_at`, `target_at`;
anomaly adds `produced_at`; Action proposal adds `proposed_at`. Timestamps and
identities remain caller-supplied. Anomaly rules are `:above`, `:at_or_above`,
`:below`, `:at_or_below`, never an inferred comparison. The accepted tensor dtype
also represents the threshold before comparison. Output-schema kind validation
must prevent Action proposals being relabelled observations or vice versa.

`Encoded` preserves `batch`, `schema`, `feature_order`, `timestamps`, `provenance`
and `layout: :feature_tuple_values_masks_quality_vector`; `Encoded.batch/1`,
`feature_order/1`, `schema/1`, `timestamps/1`, `provenance/1`, `layout/1`,
`row_count/1` and `template/1` are accessors, not new admission boundaries, and
consumers MUST use them instead of struct fields. `Encoded` implements
`Nx.LazyContainer` by delegating to its batch. Prediction exposes
`id`, `thing_id`, `affordance_type`, `affordance_name`, `value`, `produced_at`,
`target_at`, `unit`, `metadata`. Anomaly exposes `id`, `thing_id`,
`affordance_type`, `affordance_name`, `score`, `anomalous?`, `threshold`, `rule`,
`produced_at`, `metadata`. ActionProposal exposes `id`, `thing_id`, `action_name`,
`input`, `proposed_at`, `metadata`. These three output-only structs are produced
by Decoder; they do not expose separate public `new/1` constructors. Every
output struct and `Observation` expose `to_map/1`, a read-only plain-map view
for consumers that must not depend on opaque struct fields (for example a wire
conversion); the view is not a constructor and grants no admission. Observation
output uses the Observation contract above. No output carries an execution
callback or an authorization decision.

## Errors, effects and execution lifecycle

`Error` exposes stable `code` and `phase`; `message` and `details` are explanatory,
not a parsing protocol. Phases are `:construction`, `:window`, `:encoding`,
`:unit`, `:output`, `:limit`. Invalid options/forged values, mismatched identity,
DataSchema violations, bounds, unavailable unit conversion, normalization
overflow, dtype overflow and incompatible output tensor return typed errors,
not partial batches or dispatched operations. `:unit_conversion_required`,
`:invalid_unit_converter`, `:unit_conversion_failed`, `:normalization_overflow`,
`:dtype_value_out_of_range` and `:non_finite_value` remain distinguishable.

The sole consumer callback is
`UnitConverter.convert(value, source_unit, target_unit, data_schema, config)`
returning `{:ok, converted}` or `{:error, reason}`. Its output MUST be revalidated.
It MUST NOT mutate canonical state or execute a Thing Action. The consumer is
responsible for callback runtime/containment; numerical row/work limits are not
a callback deadline or OS memory sandbox. No package function owns a database,
clock, backend choice, model, credential, application callback, retry or worker.

Calls do not retain mutable cross-request state. A consumer may invoke independent
calls concurrently; any shared callback state is consumer-owned. There is no
package shutdown/drain/checkpoint API. After caller failure, the consumer may
rerun the same admitted inputs; deterministic value semantics do not promise
bitwise equivalence across untested Nx backends or runtime cohorts. Never turn
numerical output into authorization, learned state or canonical truth here.

## Security and claims

Use exact Thing identity and affordance categories at every boundary, never a
name-only join. Reject closed-input violations before numerical work. Resource
bounds cover the declared observation/row/feature/width/work dimensions, not
unbounded consumer metadata or arbitrary backend allocation. The consumer must
apply ingress payload limits and control unit callbacks and numerical backends.
Metadata and provenance are caller data, not an authorization capability.

TD 1.1 Recommendation 2023-12-05 supplies DataSchema/affordance meaning through
the public core package. Tensor windows, quality codes and inert numerical outputs
are project extensions, not a W3C numerical profile or certification. Nx 0.13.1
is the declared dependency cohort; broader backend/version claims require evidence.

## Executable acceptance

| Contract | Owning executable evidence |
| --- | --- |
| Observation/feature/schema construction, identity, bounds and closed options | `test/wotex/nx/observation_feature_schema_test.exs` |
| Window order/ties/age, units, fill masks, quality, encoded batch, unknown row features, accessors, template and lazy container | `test/wotex/nx/window_encoder_test.exs` |
| Binary-search latest/exact/nearest selection equivalence to an exhaustive reference, reversed input, empty windows and age boundaries | `test/wotex/nx/window_selection_property_test.exs` |
| Conjunctive schema checks, revalidation, overflow and finite conversion | `test/wotex/nx/numerical_integrity_test.exs` |
| Fixed-shape generation and preservation | `test/wotex/nx/shape_property_test.exs` |
| Exact decoder tensor admission, all inert kinds and anomaly comparisons | `test/wotex/nx/decoder_test.exs` |
| No application callback and stable quality codes | `test/wotex/nx/library_contract_test.exs` |

Any change to the contracts above must add both accepted and rejected boundary
examples to the owning tests. Archive and independent-consumer evidence follow
`docs/plans/wotex-nx-completion.md`; repository tests alone do not discharge them.

## Evidence

Tests cover scalar and fixed-array DataSchemas, deterministic feature order,
window selection/ties/max-age, units, shapes, dtypes, masks, quality, missing
policies, normalization, limits, Nx batches, all output kinds, and negative
authority/application-callback checks.

## Compatibility and stability

Window selection sorts each feature group once and selects by binary search;
the selection-work admission score is `n + count * features * L(n)`, where
`n` is observation count and `L(n)` is 1 for zero/singleton input and
`ceil(log2(n))` otherwise. A positive `max_work` equal to the score is admitted;
a smaller positive budget returns `window_work_limit_exceeded` before indexing.
This deterministic score is not the total number of sorting/search comparisons,
CPU reductions or backend allocations. Sorting still costs `O(n log n)`;
observation and row limits apply independently. Exact score/budget boundaries
for all three strategies, empty input, singleton input and powers of two are
covered by `window_selection_property_test.exs`.
Any selection implementation is compatible only when selected observations,
timestamp/ID tie-breaking, row order, missing markers and age rejection remain
identical to the exhaustive reference in the property tests. The bound does
not imply a measured latency guarantee.

Version `1.2.0` reconciles the obsolete scan-based table with the existing
selection-work score and makes its zero/singleton convention explicit. This is
a documentation/evidence correction, not a change to accepted budgets or
selection results. No mask, tensor, quality or output behavior changes.

Version `1.1.0` of this specification inverts the mask polarity to
`1 = observed`, `0 = filled` (a pre-release contract correction aligning with
`Nx.Batch.pad/2` and Axon mask conventions), adds `unknown_row_feature`, host
side finite checks, the `Encoded` accessors and template, and the batch-axis
statement. Version `0.1.0` defined the initial public contract. Changes to batch layout,
quality codes, tie-breaking, ports, or inert output fields are compatibility
changes and require explicit release notes and tests. W3C and Nx claims remain
pinned in the provenance document.
