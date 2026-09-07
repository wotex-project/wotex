# WLB.03: Nx experiments and numerical adoption

Specification version: 0.1.0. Contract: accepted. Numerical semantics inherit
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
The run uses process-local `Nx.with_default_backend/2`, restores caller state,
and explicitly selects `Nx.Defn.Evaluator`. It does not mutate global Nx
configuration. `target/1` accepts the one-feature values/masks/quality container
guaranteed by its good-quality, missing-error input contract. It is not a
general missing-value model. The reference callback handles only K↔Cel;
identity units are handled by the encoder; other conversions fail explicitly.

## Required experiment lanes

| Lane | Public composition | Acceptance |
| --- | --- | --- |
| `thermal-nx` | Small deterministic defn and explicit converter | Feature order, masks, quality, timestamps, provenance, output identity and unchanged effects asserted |
| `window-anomaly` | Exact/latest/nearest windows; all inert decoder kinds | Permuted input/ties, stale time, wrong Thing/category, missing fills, rejected quality, units, integer/float limits and dtype-rounded threshold cases |
| `serving-batches` | Explicit `Nx.Serving` under instance supervision | Inline and process paths agree within declared tolerance; batch padding/keys, timeout, concurrent caller correlation, stop and overload tested |
| `axon-room-model` | Small consumer-owned Axon model over synthetic room dynamics | Reproducible training/evaluation split; held-out score compared with persistence baseline; saved parameters and model/schema digests; no implied model quality from successful conversion |
| `backend-cohort` | BinaryBackend/Evaluator and explicit EXLA CPU profile | Same fixtures and shape/error contracts; declared absolute/relative tolerance for permitted rounding; device transfer and cleanup measured; no GPU required for first success |
| `proposal-policy` | Decoded proposal -> consumer decision -> simulated effect | Deny/expired/wrong-identity/stale-state decisions dispatch nothing; admitted attempt dispatches at most once within this simulated host |

All lanes are required for WLB.03 completion. Backend profiles are selected by
the host; Lab MUST NOT fetch artifacts or change application-wide Nx defaults.
Axon and EXLA belong to their explicit integration profile, not the base graph.
Named `Nx.Serving` instances use caller-supplied names compatible with the
pinned Nx release, never names generated from untrusted scenario strings.

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

`thermal_test.exs` checks the foundation against public core/Nx APIs. Full
acceptance requires each lane above in a Livebook and automated scenario with
positive, negative and resource cases. This supplies independent-consumer
evidence toward WNX-C01–C05 and WTX-C03/C04. It does not replace their native
error matrices, archive gates or stable-API decisions. There is no W3C
numerical profile, autonomous physical control or general model-serving claim.
