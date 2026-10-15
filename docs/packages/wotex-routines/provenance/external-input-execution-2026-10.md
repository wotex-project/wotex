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
