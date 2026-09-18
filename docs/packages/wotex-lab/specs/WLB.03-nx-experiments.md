# WLB.03: Nx experiments and numerical adoption

Specification version: 1.5.1. Contract: accepted. Numerical semantics inherit
`wotex_nx:WNX.01`; Lab owns inputs, execution, experiments and policy examples.

## Primary audience and entry point

Nx users MUST reach a useful tensor and inspectable result without a broker,
server, hardware, model download or native compiler. `Examples.Thermal.run/0`
is the foundation: public TD parse -> Property DataSchema -> observations ->
explicit `K` to `Cel` callback -> rows -> `Encoded.batch/1` -> a caller-selected
`defn` evaluator -> `Decoder.decode/3` -> inert `setTarget` proposal.

The fixture defines the exact Thing ID and two observations at times 0 and
1,000 with values 293.15 K and 295.15 K. The f32 Celsius batch is approximately
[20, 22]; mean plus one produces 22 Cel, inside Action input limits [5, 35].
`run/0` uses process-local `Nx.with_default_backend/2` with `Nx.BinaryBackend`,
restores caller state, and explicitly selects `Nx.Defn.Evaluator`; `run/1`
accepts closed `backend:` and `compiler:` options so the same pipeline runs on
a profile the caller already started. It does not mutate global Nx
configuration. `target/1` reads the
values and masks of the one-feature container and computes the mask-weighted
mean, so a filled row (mask `0`) never contributes; masks use `1` for observed
per `WNX.01` 1.2.0. It is not a general missing-value model. The reference callback handles only K↔Cel;
identity units are handled by the encoder; other conversions fail explicitly.

## Required experiment lanes

| Lane | Public composition | Acceptance |
| --- | --- | --- |
| `thermal-nx` | Small deterministic defn and explicit converter | Feature order, `1 = observed` masks, mask-weighted target, quality, timestamps, provenance through `Encoded` accessors, output identity, caller backend option and unchanged effects asserted |
| `window-anomaly` | `Examples.WindowAnomaly` over the versioned `Simulators.Thermal` stream: exact/latest/nearest windows, mask-weighted anomaly score, persistence prediction and observation decoding | Deterministic seeds, permuted input, stale time, wrong Thing, missing fills with mask zero, rejected quality codes, units, integer dtype limits, dtype-rounded thresholds and output shape/dtype rejection in `window_anomaly_test.exs` |
| `serving-batches` | Explicit `Nx.Serving` under instance supervision | Inline and process paths agree within declared tolerance; batch padding/keys, timeout, concurrent caller correlation, stop and overload tested |
| `axon-room-model` | Small consumer-owned Axon model over synthetic room dynamics | Reproducible training/evaluation split; held-out score compared with persistence baseline; saved parameters and model/schema digests; no implied model quality from successful conversion |
| `backend-cohort` | BinaryBackend/Evaluator and explicit EXLA CPU profile | Same fixtures and shape/error contracts; declared absolute/relative tolerance for permitted rounding; device transfer and cleanup measured; no GPU required for first success |
| `proposal-policy` | Decoded proposal -> consumer decision -> simulated effect | Deny/expired/wrong-identity/stale-state decisions dispatch nothing; admitted attempt dispatches at most once within this simulated host |

All lanes are required for WLB.03 completion. Backend profiles are selected by
the host; Lab MUST NOT fetch artifacts or change application-wide Nx defaults.
Axon and EXLA belong to their explicit integration profile, not the base graph.
Named `Nx.Serving` instances use caller-supplied names compatible with the
pinned Nx release, never names generated from untrusted scenario strings.

`Experiments.RoomModel.run/1` implements the Axon lane with bounded rows,
epochs and wall deadline, split-before-window construction, train-only
normalization, values/masks/quality inputs, a serialized parameter artifact,
model/schema/dataset digests and an inert decoded prediction. The explicit
EXLA CPU vector uses the same input identity and an absolute tolerance of
`1.0e-4`; transferring its device tensor back to BinaryBackend deallocates the
source device value. A timed-out experiment kills its monitored worker and
returns no prediction.

The room experiment contract is `2.0.0`. Malformed/out-of-budget counts
MUST return `invalid_experiment` before deriving a default split or starting
training, including when an explicit split was supplied. Held-out predictions
only determine held-out scores. The future decoded prediction MUST instead
use the final two observed rows, with `produced_at` at the latest observation
and `target_at` one simulator step later; its manifest names both input times.
The same training-only normalization and values/masks/quality layout apply.

Parameter artifacts use public `Nx.serialize/2` and declare `nx-serialize` in
the manifest. Restoring each admitted Binary/Evaluator and EXLA CPU artifact
onto BinaryBackend MUST reproduce that future prediction within the declared
tolerance without depending on the training worker's native buffers. This
tests trusted, locally produced artifacts; it does not admit untrusted uploads
or claim a universal cross-version format. Migration: prior raw external-term
parameter blobs must be regenerated, not silently relabeled. The earlier
future result mislabeled the final held-out estimate and cannot be compared as
the same forecast. Architecture `axon-room-v1` and held-out scoring stay the
same; result metadata and the manifest bind the new experiment version.

`serving_test.exs` implements the Serving resource vectors: padding and keys,
finite timeout flush, concurrent caller correlation, instance-capacity
refusal, and termination of an executing worker and caller within the child
shutdown budget. No Serving is started by application loading.

## Dataset and experiment contract

1. Synthetic thermal, energy and actuator streams MUST be generated from a
   versioned deterministic simulator with explicit time step, seed, initial
   state, disturbance schedule and units. Record equations and coefficients;
   simulated data MUST be labeled synthetic.
2. An experiment manifest MUST record dataset digest, feature/schema order,
   window layout, admitted quality, units, missing policy, normalization,
   dtype, backend/compiler, model/parameter digests, seed, package/runtime
   cohort, split boundaries, training hyperparameters and evaluation metrics.
3. Train/validation/test splitting MUST precede windowing and learned
   normalization. Windows MUST NOT leak observations across split boundaries.
   Training statistics derive solely from the training split. Model metrics
   MUST compare with a named baseline on the same held-out inputs.
4. Values, masks and quality codes MUST all be visible to the model contract.
   Bad-quality or filled data cannot silently become a trustworthy signal.
   Limits cover rows, width, windows, work, batch bytes and inference deadline.
   Shape/backend errors and cancellation MUST produce evidence, not effects.
5. Numerical outputs MUST be decoded through WNX.01 before policy use. Policy
   MUST bind exact Thing/Action/input, proposal/attempt identity, observation
   age, expiry and current simulated state revision. Authorization, rejection,
   dispatch and observed result are distinct records. Neither a confidence
   score nor a formal result grants authority.
6. Replay compares numerical values under the pinned tolerance and separately
   compares exact identity/provenance/schema/decision fields. Elapsed time,
   floating point output and training are not universally byte-deterministic.

## Acceptance and ownership

Exploratory dataframe work follows the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).
Explorer is optional and distinct from Nx computation and chart rendering.
Its analytical previews must preserve units, missing/nonfinite states and
source provenance. Conversion of nullable series to tensors requires an
explicit missing policy and the existing values/masks/quality contract; a
dataframe summary is not a new numerical admission or training-data path.
No Explorer, Kino or chart dependency is necessary for `Thermal.run/0`.

`thermal_test.exs` checks the foundation against public core/Nx APIs and
`window_anomaly_test.exs` covers the bounded `window-anomaly` lane;
`serving_test.exs`, `room_model_test.exs` and `backend_cohort_test.exs` cover
Serving, Axon and EXLA; and `smart_room_test.exs` covers the proposal-policy
lane. The versioned simulator admits at most 4,096 samples and 256 scheduled
heater/glitch entries and records step, seed, initial state, disturbances,
units and its synthetic label. The `thermal-nx`, `window-anomaly`,
`serving-batches`, `axon-room-model` and `smart-room` Livebooks execute the
same positive, negative and resource contracts. This supplies independent-consumer
evidence toward WNX-C01–C05 and WTX-C03/C04. It does not replace their native
error matrices, archive gates or stable-API decisions. There is no W3C
numerical profile, autonomous physical control or general model-serving claim.

`priv/provenance/WLB.03-evidence.json` records the fixed-seed local cohort:
all six required lanes pass across 52 tests. Its three exclusions are the
separately owned real-broker cases from WLB.04, not WLB.03 lanes. The record
binds the thermal fixtures, exact source/lock cohort, Binary/Evaluator and EXLA
CPU backend profile, and zero surviving Serving/device/effect resources.
