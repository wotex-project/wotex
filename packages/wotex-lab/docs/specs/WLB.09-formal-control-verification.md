# WLB.09: Optional formal control verification with ex_maude

Specification version: 0.1.0. Contract: accepted.

## Decision and scope

`ex_maude` belongs at the **consumer policy experiment boundary**. Nx produces
numeric proposals; Maude explores modeled rewrite transitions and conflicting
control rules; consumer policy decides authority. WoTEx core/Nx/Runtime remain
independent of Maude. This profile is optional to activate but required to
implement and verify before the Lab programme is complete.

Use the published `ExMaude.Pool.child_spec/1` and public load/search operations
with an explicit instance-owned pool. The port backend is the reference choice;
no NIF or C-node is needed. The foundation does not depend on `ex_maude`, start
a pool or download a binary. Exact package/model/binary versions and hashes
are inputs to the profile, not selected by a remote assistant.

## Model contract

The pinned `thermal-control-v1` model has finite temperature bands, actuator
modes, energy-limit states, proposal identities, approval states and bounded
delivery/observation age. Define an explicit abstraction from WNX outputs and
smart-room state into these terms, including units, threshold rounding and
information lost by discretization. State and transition definitions are
checked-in executable model source, separately licensed and digest-addressed.

Required properties: heat and cool are never simultaneously admitted; no
dispatch without a matching unexpired decision; stale observation cannot
authorize a proposal; an energy-limit refusal cannot be bypassed by reordering;
a duplicate intent cannot create a second simulated effect. Include safe
models, deliberately broken models and reachable counterexample traces.

## Execution and result contract

1. The profile MUST accept a known model ID/digest, admitted finite inputs,
   explicit pool, max depth (100), solution limit (1), wall deadline (5 s) and
   output ceiling (1 MiB) by default. Per-profile hard ceilings bound overrides.
   Raw remote Maude commands, modules, include paths and host files are refused.
2. A host serializer MUST encode only known model terms; caller input cannot
   become command syntax. Use public ExMaude validation/encoding where its
   actual model matches, otherwise a closed Lab serializer with hostile-input
   tests. Existing ExMaude IoT/AI models are not automatically equivalent to
   the thermal model or to W3C semantics.
3. Results distinguish `counterexample`, `verified_in_model`, `inconclusive`,
   `timeout`, `unsupported` and `error`. A bounded search returning no solution
   is **inconclusive** unless complete state-space exhaustion is explicitly
   established for the declared finite model and query. Search output lacking
   exhaustion evidence cannot be promoted to verification.
4. Evidence MUST contain model/abstraction/input/query digests, engine and
   package versions, explored bounds, exhaustion basis, result and replayable
   counterexample references. `verified_in_model` applies only to those inputs,
   abstractions and modeled transitions, never an unmodeled physical system,
   probability estimate, ML accuracy claim or W3C certification.
5. A counterexample MUST replay as an ordered, finite simulator trace under
   WLB.05. Divergence is a recorded abstraction/replay error. Either outcome
   leaves proposals inert. Runtime policy cannot treat a verifier result as an
   authorization token or reuse it after a model/state/input revision changes.
6. Cancellation, worker crash, output overflow, malformed response, timeout
   during model load and concurrent pools MUST terminate boundedly and preserve
   instance isolation. The host must verify whole subprocess-tree cleanup;
   an Erlang Port timeout alone is insufficient.

## Binary and distribution boundary

`ex_maude` 0.4.1 is the inspected package API cohort. Its package is MIT; Maude
is a separately installed GPL-licensed executable. Provisioning MUST be explicit,
digest verified and accompanied by exact license/provenance notices. No silent
installer or redistribution license assumption is allowed. Missing executable,
unsupported architecture or unverified digest gives `unsupported`/admission
failure, never an empty successful report. Nerves and base Nx modes remain
usable without this profile. Licensing is documented per actual selected binary.

## Acceptance

The formal-control notebook and automation run one valid finite model, each
broken property, no-solution depth exhaustion, timeout, malformed/oversized
output, unavailable binary, command injection attempt, pool restart and two
concurrent isolated instances. A counterexample is replayed in smart-room;
changing model/input digest invalidates attached evidence. An Action counter
remains unchanged throughout verification. This is model-scoped evidence and
does not substitute for package conformance or consumer authorization.
