# External input execution source-gap review

Reviewed: 2026-10-15. This is negative public-API evidence motivating the
[accepted successor](../specs/external-input-execution-v1.md). It is not positive
execution/archive acceptance for that successor. Its entry schemas, independent
vectors, implementation and EIX-T1–T6 are still required.

## Inspected cohort and actual probe

The executed independent consumer selected Routines source
f3e77a431a917b639f7b0d52a93b78c27def4344, core/Profiles/Continuum source
687a5cd70267fa47dbfb36e28eccad6ef2964fdf and its locked dependencies.
Current repository source was inspected at 10e43a4a. No dependency version or
source was changed by this review. The consumer ran `mix run --no-start -e`
through its pinned Elixir 1.19.6 / OTP 28.5.0.6; the probe exited zero.

The input is the shipped priv/vectors/wro-05-input.json record. Public
Input.project/4 successfully creates its expected integer Fact, value 2510.
The probe compiles a manual source with one sensor binding, condition gt 2000,
noop step, run_ms 1000, overlap reject and no parameters. Context includes the
vector's Registry and complete Basis, exact legacy_basis_ref, Fact Thing ID,
empty resource roles/definitions/arguments and explicit compiler basis. Profile
uses the existing evaluation-test ceilings: source_bytes 65536, source_depth 32,
expanded/predicate nodes 64, invocation/parallel 4, effects/waits 16,
active definitions/runs/pending work 64 and run_ms 86400000. Limits are the
vector's explicit Limits.

Snapshot has one active IR digest, one resource at revision 1, the joined Fact
and its complete four-field binding basis. Time uses the Fact receipt epoch,
elapsed_ms equal to its original receipt_ms, clock generation clock:1 and UTC
low/high ten milliseconds after the original trusted source timestamp. These
coordinates keep the source fresh under the vector's independent uncertainty.

| Probe | Actual observed result |
| --- | --- |
| Preserve joined Fact's external profile digest in snapshot binding basis | Snapshot.new/4 refuses stale_binding_basis |
| Put installed Basis semantic digest in binding basis, leaving Fact unchanged | Snapshot.new/4 succeeds; Evaluation.evaluate/5 returns unknown rather than true |
| Add one microsecond to original Proposal receipt, keeping the exact mapping and metadata | Input.project/4 refuses inexact_conversion |
| Set only metadata.received_at to null | Input.project/4 refuses invalid_input |

The distinct vector identities are externally checkable: Basis semantic digest
is sha256:ce4f001727d316aee807ccef0a278c9e70ba03c68e2600e7854713abf3367b2d;
the Fact's external profile digest is
sha256:031cebb281a8a231f2624a0f3486c2f6bc32bb871a2c536e7175cee8e5d35329.
Both are valid identities with different owners. Rewriting one to the other
would discard correspondence rather than complete the public execution join.

The probe asserted all four outcomes using actual public Compiler, Input,
Snapshot and Evaluation calls. It used no stubs, Store, hardware, transport or
relabelled result. It does not establish a positive Kernel/edge path, installed
clock correlation, current source authority or physical qualification. The
existing scalar representation/archive evidence retains its earlier scope.

## Contract review and validation

The successor separately defines required-but-null receipt UTC, an explicit
closed floor clock alternative with exclusive bounded expiry, and an installed
external binding preserving both profile and Basis identities. It names all
native/schema/edge/model boundaries and independent signed arithmetic,
replacement, absence and full reader-to-kernel/archive cases. Its normal and
adverse traces can be followed without the originating research conversation.

No implementation or schema has been promoted to passed evidence. The package
catalogue marks the new WRO.05 execution obligation partial, preserves its
existing implemented scalar subset and links the completion order.

Documentation checks used the repository's Elixir 1.20.2 / OTP 29.0.4 lane:
`mix wotex.catalogue` rendered 103 working specifications; `mix docs.check`
passed all 517 tracked Markdown files and the current family catalogue. A
disposable projection of indexed Markdown/package catalogues used the public
Catalogue.write/2 and check/2 APIs to generate and validate all 103 indexed
specifications. Only that generated projection was staged; unrelated research
metadata remains outside the commit. All 13 changed-document relative links
resolve to indexed files, and the three owning versions match both working and
indexed catalogues. Both Git whitespace checks passed.

The metadata projection was removed. No dependency download, application suite,
Dialyzer, native build, Docker resource or physical campaign ran. The executed
probe is negative evidence; none of EIX-T1–T6 is promoted by these prose checks.

## Frozen entry artifacts

The new wro-05-input-execution schema defines disjoint exact/floor clocks and
legacy/external bindings. Existing embedded Fact/snapshot/edge definitions are
updated consistently in all eight affected schemas, using local references only.
The independent vector retains the complete mapping/registry/proposal, expected
Fact/binding and original proposal hash. Eleven frozen signed-floor cases cover
sub-millisecond boundaries, a 65-bit difference, negative projection and expiry
overflow. Python's integer floor division and sorted UTF-8 JSON SHA-256 supplied
the oracle; its serializer first reproduced the previous mapping digest exactly.

The first schema run (seed 325491) passed the two existing cases but invalidated
six new cases because the validator does not accept a JavaScript Unicode escape
in a regex. Replacing it with the equivalent hex escape corrected the offline
meta-schema; a fixture assertion message was also corrected to a string.
The final command `mix pkg wotex-routines test test/wotex/routines/input_execution_schema_test.exs test/wotex/routines/schema_test.exs --warnings-as-errors`
passed **8 tests**, seed **652228**, in **0.1 seconds**. Scoped formatting and Git
whitespace checks passed. Runtime constructors, public binding/execution joins
and archive/mutation cases remain unimplemented; these are entry-shape checks.


## Native execution slice

The native implementation accompanies this record, descending from entry artifact
commit 1fd215a7. The eight changed production modules are Edge, ExternalBinding,
Fact, Input, InputMapping, InputValidation, ObservationView and Snapshot under
packages/wotex-routines/lib/wotex/routines/. Their source manifest SHA-256 is
8f92907a96b9dd7b145da251032bc05e6fd510a7dac344b55b4c7f38e84af785. Reproduce it by sorting those repository-relative
paths, concatenating each path, NUL, its lowercase file SHA-256 and newline, then
hashing the UTF-8 concatenation. No producer version, consumer pin or lock changed.

Fact keeps required-but-null receipt UTC through Input and an actual Continuum
round trip; unknown source UTC still refuses exchange. Input's explicit floor
clock passes all eleven independent integer vectors, checked expiry and closed
clock grammar refusals. The old exact clock still refuses unaligned input.
Input.binding_basis/3 embeds the fully revalidated installed Mapping. Snapshot
and Edge compare its entire Basis body, outer identity and regenerated program
Registry. ObservationView retains the external profile and requires exact mapped
class, source clock basis and target receipt epoch. A foreign receipt incarnation
cannot become current by pairing it with an equally foreign Time epoch.

The new input_execution_test.exs suite uses actual public Profiles compiler and
interpreter output for integer, Boolean and enum evaluation/completed inert
Kernel runs. It executes the frozen five-row external edge trace through both
Edge and Kernel, plus expiry, restored/retained/replayed input, source/clock
replacement, outer/native forgery, complete Basis and aggregate-bound refusals.
An otherwise permissive Basis demonstrates that changed source class/clock
becomes unknown specifically at the external correspondence guard. Existing
analysis scopes explicitly refuse this external-input program. The new schema
suite remains shape evidence, separate from these executed public transitions.

The final focused command selected input_execution, input_execution_schema,
input, input_mapping, basis, evaluation, edge and model test files with
--warnings-as-errors: **63 passed**, seed **626045**, **4.4 seconds**. Earlier
runs exposed invalid test scope/evidence and raw Limits fixtures, then a bound
fixture which changed the compiler's selected Limits identity. Those fixtures
were corrected without broadening the owning APIs; the final bound case
regenerates its Program under the narrowed Limits before testing the Snapshot.
The first fast gate exposed pipe formatting, unused-variable convention and
complexity issues. Fact identity and external correspondence remain separate
small checks; no warning suppression was added. The final
`mix check.fast --package wotex-routines` passes compilation, formatting, strict
Credo and **179 tests**, seed **929185**, **7.8 seconds** for tests (**11.4 seconds**
for the gate). `mix dialyzer.pkg wotex-routines` reuses the current PLT and reports
**zero errors**, **1.76 seconds** analysis. All commands used Elixir 1.20.2 /
OTP 29.0.4 from the repository toolchain.

EIX-T1–T5 have native software checks; EIX-T6's two extracted execution consumers,
behavioral identity/rounding mutations and renewed producer-absence path remain
pending. The owning full package milestone is deferred to that coherent archive
slice. The shared working tree contains unrelated research, so affected-package
discovery at HEAD names all twenty packages; checks deliberately select only
Routines. No native/container lane, host admission or physical qualification is
claimed. Temporary metadata projections and generated documentation are removed
after validation; reusable dependency/build/PLT caches are retained.

The updated ExDoc build passes --warnings-as-errors with its output in a
context-managed temporary directory, removed on completion. `mix docs.check`
passes all 517 tracked Markdown files and the current 103-entry family catalogue.
The indexed catalogue is separately generated and checked from projected indexed
owning documents, preserving unrelated research changes.


## Extracted execution milestone

The production cohort is repository commit **743ef568**, including the native
implementation above. Only the archive runner/consumer tests and repository
documentation changed after that source commit; shipped package members did not.
The existing archive runner built all five archives with WOTEX_PATH_DEPS unset
and extracted them into one disposable workspace. Consumer Mix projects use only
those explicit extracted paths plus their resolved locked Hex dependencies.
The command was
`mise exec -- mix pkg wotex-routines run --no-start bin/check_archive.exs --profile-consumers`
on Elixir 1.20.2 / OTP 29.0.4. It exited zero.

| Extracted archive | SHA-256 |
| --- | --- |
| wotex_routines | fb74f71b6b44b286907d65caaf2271e9e0b6318939236a4aaf736120e42a33ef |
| wotex | 77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61 |
| wotex_continuum | db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5 |
| wotex_runtime | 5d8cd7e3012dd2115b63ccc5c4fe67130ab06a82253405c452970abb8d210df7 |
| wotex_profiles | 34a3dcef363a0b072fa2b260efeff8633f8365fd4aecfd1fbbc2c268c82e0b96 |

Industrial and research consumers each pass **five cases**, seeds **799943** and
**407589**, **0.5 seconds** each. Their distinct quantity correspondences yield
2510 centidegrees and 251000 millionths respectively from the public reader.
They retain external profile identity, original signed -1001 us receipt, projected
9998 ms, exclusive expiry 10998 ms and null receipt UTC through actual Compiler,
Snapshot, Evaluation and Kernel calls. Replacing only Fact.profile_digest with
the Basis digest becomes unknown/blocked. The independent edge rows require
baseline, eligible, duplicate, unqualified and baseline, with no effect proposals
or catch-up root. Both public Edge and Kernel agree on retained complete binding.

Each family runs a separate five-case baseline at seed 0, then two fresh BEAM
processes recompiling a single module from that exact extracted artifact. Removing
the Fact/external profile identity comparison causes **one assertion failure**;
replacing Integer.floor_div with truncating div causes **two assertion failures**.
All **four mutants** are caught. The harness requires unchanged test totals,
positive assertion counts and zero non-assertion errors; compilation/process/
formatter failure cannot count as a killed mutant. It never edits repository
source or the pristine extracted dependency.

The producer-absent consumer passes **one case**, seed **822062**, **0.05 seconds**.
InputMapping.new/3, Input.project/4 and Input.binding_basis/3 return
missing_producer, while an ordinary zero-binding source compiles and completes
an actual inert Kernel run. The reader remains unloaded. Representation-only
checks from the prior archive corpus remain in both positive families.

Positive consumer locks share SHA-256
6ddb05e87f2872a12a244a022d666372d792510c8760188a3ac235ce53c258dd;
the absent consumer lock is
b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f.
Resolved Hex dependencies are Decimal 3.2.0, ExJsonSchema 0.11.5, Jason 1.4.5
and Telemetry 1.4.2 in the positive families; the absent closure excludes
Profiles/Runtime/Telemetry. No released dependency selection was changed.

| Harness/input source | SHA-256 |
| --- | --- |
| bin/check_archive.exs | ce0bd89e1e75a6c0500170fb8ce5531881249f5c8621adbfbe7ead1ef8e93892 |
| test/support/archive/profile_consumer.exs | 515760202201325fcd0b00c134ba44747bad22a0b230054a0baf0944c8f84a80 |
| test/support/archive/profile_absent_consumer.exs | 8f8bbe232b1121482c1e962d705f6aca837fbed3f39a053be776b8a621b37bfe |
| test/support/archive/profile_mutation_consumer.exs | 4aed8a9c005cc6d8ce2362642d2bf580b15379ac9d1ad83c6c1843e8df01a1ef |
| priv/vectors/wro-05-input.json | dbbb5a65af5f8a875174ebcd7ff547f3eb8c688cd31473a0314674bdf23ed6ed |
| priv/vectors/wro-05-input-execution.json | 682f03b7de505841d0f2e284fae27c6348295daf34e5c4c3b2ebb034ff221121 |
| mix.lock | 13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22 |

The owning full milestone command
`mise exec -- mix pkg wotex-routines check --no-retry` passes in **22 seconds**:
**179 tests**, seed **797568**, **7.7 seconds**, **95.4% coverage**, compilation,
formatting, strict Credo, Doctor, ExDoc, Dialyzer, both dependency audits, locked
dependency/unused checks, consumer boundary, archive, application-free and Git
whitespace checks. Doctor reports 58 passing modules and 100% doc/moduledoc/spec
coverage; Dialyzer reports zero errors in 1.69 seconds with the current PLT.
The ordinary archive gate independently reproduces the Routines archive digest
above. The root all-package gate and unrelated/native/host/physical campaigns
were not run; unrelated root documentation makes broad affected discovery name
all twenty packages.

EIX-T1–T6 and WRO05-T6 now have bounded software evidence. WRO.05's selected
scalar/external execution contract is implemented. This does not qualify a real
consumer's clocks, sources, Store admission, handoff, device effect or wider
analysis model. Home has not selected this new source by this package milestone.

Both archive workspaces are removed by the runner's after block. The newly
generated package doc/ directory was removed after recording gate results; no
cover/ directory remains. Dependency, build and PLT caches are retained. No Docker
image, container or volume was created. No ref or release was pushed/published.
