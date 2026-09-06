# Wotex Nx completion contract

Plan `WNX-C`, revision `1.0.0`. This immutable work-definition baseline has no
rolling completion state. Preserve IDs; scope changes require an explicit
successor. Catalogue implementation status is about WNX.01, not production,
release or stable-API admission.

## Implementation authority

WNX.01 owns the closed constructors, Window/Encoder/Decoder operations, tagged
errors, exact dimensions, quality mapping and inert output types. The core owns
DataSchema and WoT semantics. The consumer owns observation admission, canonical
state, clocks, model execution, backends, training, policy and Action dispatch.
Do not duplicate core values, introduce an application callback, start a process,
add persistence or infer a unit/backend/model to complete this plan.

Pure concurrent calls must not communicate through hidden state. Explicit
consumer unit callbacks are the sole conversion port and must be revalidated;
they do not transfer authorization or lifecycle ownership. A caller may rerun
admitted inputs after failure; no durable checkpoint or queue belongs here.
Rows, features, flattened width, observation count and work limits are explicit
but do not imply global metadata-memory limits or callback deadlines.

## Standards and remaining-claim ledger

| Claim ID | Authority / bounded existing contract | Remaining or excluded claim |
| --- | --- | --- |
| WNX-CL01 | TD 1.1 Recommendation 2023-12-05 through core DataSchema and affordance values | No W3C-standardized tensor/observation/quality profile or certification |
| WNX-CL02 | Nx 0.13.1 typed tensors and Nx.Batch layout in WNX.01 | No automatic equivalence across all backends, platforms or Nx releases |
| WNX-CL03 | Deterministic temporal selection and declared normalization | No learned statistics, clock synchronization or model accuracy claim |
| WNX-CL04 | Validated inert Observation/Prediction/Anomaly/ActionProposal values | No admission, policy, inference execution or Thing Action effect |
| WNX-CL05 | Explicit bounds and schema validation | No OS sandbox, callback time bound or arbitrary payload-memory ceiling |
| WNX-CL06 | Repository numerical tests and properties | Archive-only and independent consumer compatibility require separate proof |

`docs/provenance/standards-and-dependencies.md` pins external sources. Additional schema support
or backend claims require exact examples, revision/cohort and tests; do not
convert unsupported values into a silent coercion to make a model run.

| Claim dimension | Current status | Promotion evidence |
| --- | --- | --- |
| Value support | Observation/row/tensor metadata and inert output values follow WNX.01 | C01/02 malformed, bound, rounding and forged-value vectors |
| Operation support | Deterministic conversion/encoding/decoding cells only | Positive/negative evidence for every public operation and policy option |
| Independent interoperability | Not established | C04 independent consumer against exact archive/backend cohort |
| Profile conformance | None; W3C defines no numerical tensor profile here | Separately accepted profile contract if one emerges |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Work packages

| ID | Prerequisites | Deliverable | Executable acceptance |
| --- | --- | --- | --- |
| WNX-C01 | WNX.01 | Clause-to-test and public error matrix for each constructor, resampling, encoding and decoding | Every public operation rejects duplicate/unknown options and forged structs; exact Thing/category checks and all defined error phases have executable examples |
| WNX-C02 | WNX-C01 | Numerical boundary regression/property additions without widening supported schema scope | Integer min/max and one-beyond reject correctly; normalization and dtype overflow fail; dtype-rounded anomaly thresholds compare exactly; deterministic ties survive input permutation |
| WNX-C03 | WNX.01 | Archive-only minimal consumer fixture | Build archive, inspect dependencies/assets, unpack without source checkout, compile warnings-as-errors, and run public observation → rows → encoded batch → inert output with rejection cases |
| WNX-C04 | WNX-C02, WNX-C03 | Independent reference consumer using explicit unit callback and declared Nx backend | Exact archive roundtrip preserves feature order, shapes, masks, quality, timestamps and provenance; missing/quality/unit policies and invalid output never produce an Action effect |
| WNX-C05 | WNX-C04 | Supported runtime/backend cohort and compatibility evidence manifest | Run declared supported cohort; document numerical tolerance only where WNX.01 permits rounding; no claim of untested cross-backend byte identity |
| WNX-C06 | None | Allowlisted package documentation inputs that exclude machine-local execution records | `mix hex.build` archive listing proves docs/tasks/local absent including any local sentinel |

C01/C02 and C03 can proceed independently; C04 requires their common accepted
contract. New model execution, persistence, dispatch or a separate library is
not a deliverable. Do not use a source-path dependency as release-consumer proof.
If a matrix exposes unsupported claimed behavior, correct the owning contract
or implementation explicitly before advancing its gate; do not hide the case.

## Gate definitions

- `repository_green`: the repository's `WOTEX_PATH_DEPS=1 mix check --no-retry` quality
  alias passes, plus docs and `git diff --check`; record actual constituent
  commands, coverage and supported runtime. A smaller test command is partial
  evidence, not the full gate.
- `archive_consumer_green`: C03 passes using the exact inspected production
  archive and declared dependencies, with no development path fallback or
  application callback. Record archive SHA-256 and dependency cohort.
- `reference_consumer_green`: C02/C04 pass through public functions with an
  independent consumer fixture and explicit backend/unit policy for that archive.
- `public_release_candidate`: preceding gates, C01/C05, license/provenance and
  bounded claim review pass. Reaching this state does not authorize publishing,
  tagging or pushing.
- `stable_api_candidate`: release-candidate proof plus explicit review of all
  value fields, ports, tensor/batch layout, masks, quality codes, tie rules,
  errors and inert outputs; no unresolved advertised compatibility promise.

Each proof binds source commit, runtime, dependency/backend cohort, commands and
exit codes. Archive consumers additionally bind archive digest. Changes affecting
those identities invalidate the corresponding proof until rerun.

## Local execution records

Only `docs/tasks/local/wotex-nx-tracker.yaml` holds mutable progress. Package
inputs allowlist publishable documentation and structurally exclude the ignored
path; every candidate archive still proves WNX-C06 because `.gitignore` is not
an archive boundary. Schema: `schema_version: "1.0.0"`,
`plan_id: WNX-C`, `plan_revision: "1.0.0"`, `work_items` with `id`,
`state` (`queued|active|blocked|verified`), `prerequisites`, `evidence`
(source_commit, archive_sha256 when applicable, runtime, dependency_cohort,
backend, command, exit_code), and `remaining_claims`. Missing evidence is null,
not an assumed pass. Neither this plan nor the catalogue is an audit tracker.
