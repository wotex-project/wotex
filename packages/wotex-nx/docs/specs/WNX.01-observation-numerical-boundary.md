# WNX.01: Observation and numerical boundary

**Status**: Implemented development contract

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
8. Encoding MUST produce typed values, missing masks, quality codes,
   deterministic feature slices, provenance, and an `Nx.Batch` without starting
   a process or selecting a backend. Each batch entry is
   `{values_tuple, masks_tuple, quality_vector}`. Both tuples follow feature
   order; the quality vector uses `good=0`, `uncertain=1`, `bad=2`, and
   `missing=3`.
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

## Evidence

Tests cover scalar and fixed-array DataSchemas, deterministic feature order,
window selection/ties/max-age, units, shapes, dtypes, masks, quality, missing
policies, normalization, limits, Nx batches, all output kinds, and negative
authority/application-callback checks.

## Compatibility and stability

Version `0.1.0` defines the initial public contract. Changes to batch layout,
quality codes, tie-breaking, ports, or inert output fields are compatibility
changes and require explicit release notes and tests. W3C and Nx claims remain
pinned in the provenance document.
