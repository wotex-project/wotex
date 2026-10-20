# Independent verified-decision archive profile

Version: 0.1.2. Updated: 2026-10-20. Status: implemented archive lane;
both extracted consumers and all twelve semantic mutations pass.
Owner: [verified decisions](../specs/verified-decision-v1.md), principally
VD-02–08 and VD-T11–T14. This profile makes those archive obligations concrete;
it neither replaces the broader native matrix nor widens any runtime grammar.

## Result, inputs and ownership

Two separately implemented consumers must exercise the public Transition and
Decision boundaries against one exact extracted core/Continuum/Routines cohort.
Each consumer uses independent expected behavior and rejects semantically wrong,
well-shaped and rehashed claims. Merely comparing a forward result with the
checker, accepting a schema or changing a test label is insufficient.

The opt-in entry is `bin/check_archive.exs --decision-consumers`. It builds
archives through the existing package builders, verifies the ordinary archive
file boundary, extracts them into a fresh disposable absolute workspace and
creates separate `source` and `journal` Mix consumers. Each project declares
only those extracted path dependencies with `env: :prod, override: true`.
WOTEX_PATH_DEPS, inherited build/dependency paths and their roots are cleared;
no neighboring checkout supplies consumer code. No ExBooking, optional profile
reader, interpreter, database, transport, framework or native host is required.

The lane records SHA-256 for the three archives, both consumer/oracle sources,
the mutation runner and each consumer lock. The routines archive hash is the
explicit compiler basis. An identity case in each project verifies that all
used public modules, including Transition and Decision, load from that project's
extracted build and that the three libraries have no application callback.
Ordinary passive loading and a query without application startup are separate
from installed-host or physical qualification.

Both families select all twelve Profile members explicitly: source_bytes 65,536,
source_depth 32, expanded_nodes/predicate_nodes 64, invocation_depth/parallel_width
4, effects/waits 16, active_definitions/active_runs 64, pending_work 1,024 and
run_ms 86,400,000. Their six Limits are max_bytes 67,108,864, max_depth 64,
max_nodes 2,000,000, max_collection_size 8,192, max_string_bytes 65,536 and
max_integer 9,223,372,036,854,775,807. Smaller selections are explicit separate
cases with freshly compiled Programs; a checker never increases them.

Installed basis/registry/Fact declarations may be read from the shipped
`priv/vectors/wro-01.json`. They are synthetic public capability inputs, not an
oracle. All events, snapshots, original/busy/edge history, elapsed and UTC clocks,
dispositions and batch limits are explicit values. Tests perform no device
discovery, clock read, admission, persistence or physical dispatch.

## Oracle independence

The source family derives expectations from its own raw source trees, supplied
binding declarations, event/receipt history and integer coordinates. It walks
source paths rather than the compiled execution tree, derives original/path
identities and receipt digests through public canonical JSON plus SHA-256, and
checks changed and retained fields. Literal expected cuts cover complete
negative as well as positive membership. Its arbitration oracle compares all
eligible groups by complete equality signatures and intersecting domains.

The journal family owns a separate in-memory revision/receipt/charge ledger and
explicit event/time traces. Its expected originals, starts, pending contributors,
charges and conflict outcomes come from that ledger, not from a forward Run or
the source oracle. Serialization/restoration preserves its revision and history.
It independently rejects stale candidates and lost charge history before
retaining inert point data, then requires a fresh complete input/time check for
current effects. Its finite grouping/conflict expectations are independently
implemented from its own retained member records.

Neither oracle imports production execution, qualification, tree traversal,
pending, transition-checker, time-cell or arbitration helpers. They do not call
each other or copy the native decision reference helper. Public Compiler and
value constructors may prepare checked declarations; public Kernel/Collection/
Arbitration operations may prepare claims outside proof. Those returned claims
are subjects of independent assertions, never the source of expected eligibility,
cut bounds, no-repeat history or conflict outcomes. Public Transition/Decision
operations are the systems under test. Raw input declarations may be shared;
oracle algorithms and expected trace state may not.

## Cases required in both families

Each family has seven behavioral cases plus its independent cohort identity
case. A case may contain an explicit finite matrix, but no required cell may be
skipped, projected onto a simpler source or counted as passed through an error.

| Case | Required trace and independent falsifier |
| --- | --- |
| VDA-T1 | Check manual and retained point transitions under Time@1 and Time@2, including sequence/delay, wait, parallel, fixed conditional and invoked-child conditions. Verify complete paths, original identities, starts/deadlines, ordered new versus retained pending work and exact basis. A plausible rehashed motion/basis/proposal change must refuse. |
| VDA-T2 | A late receipt cannot hide a prior effect/invoke deadline or enable its dependent path. A held admission remains charged through expiry, cancellation, failed/unknown/satisfied history and restore; duplicate history creates no new charge or handoff. A coherent rehashed spent/receipt rewrite must refuse. |
| VDA-T3 | A first, reconnecting or unqualified Fact cannot invent an edge. Independently check the baseline and before/after edge fields, then reject a shape-valid false baseline/eligible transition. Cover both Edge representations through the selected Time grammars. |
| VDA-T4 | A member with no current proposal contributes its delay/wait/Fact/window boundary. Before the boundary current reuse succeeds; at it the whole decision refuses. An authenticated inert point may be retained after publication delay, preserving its original start; a fresh cut reaches the original boundary without restarting the timer. Omitting that negative member or widening/narrowing and rehashing the cell must refuse. |
| VDA-T5 | Verify complete proposed/reserved contributors, equivalents, constraints, overrides and domain conflicts before cutoff. The last supplied incompatible contributor still blocks its domain. Include the complete 64-member, 1,024-pending case before a sixteen-group cut and a separately compiled 1,023 refusal. Rehashed pending/state/group/decision omissions must refuse. |
| VDA-T6 | Relevant UTC confidence endpoints can move in either direction only inside both canonical cells. Relevant generation/presence change refuses; irrelevant UTC replacement/loss preserves elapsed work. Changed non-time input or elapsed grammar/epoch/generation/regression refuses at its owning stage. Point and checked Times and unchanged historical transitions remain explicit. |
| VDA-T7 | Closed/native boundaries and selected aggregate JSON bounds refuse malformed/forged wrappers, omitted fields, unsupported Collection@1 and exact/one-under bounds without repair. Historical point proof grants no current authority; frozen Model/Analysis requests retain their explicit unsupported scope. |

The capacity and lower-bound cases count every supplied pending original before
coalescing. Testing sixteen selected groups alone does not establish the 1,024
case. Each consumer independently establishes its expected conflict/contributor
counts. A smaller fixture cannot stand in for the specified capacity trace.

## Isolated semantic mutations

For each family, first run the actual seven behavioral cases unmodified in a
fresh VM. Then execute the same cases against each single selected mutation of
the extracted verifier source, recompiling only that module in memory or an
isolated disposable replacement. The unmodified archives and installed BEAMs
remain unchanged. The source site must match exactly once; ambiguous/missing
sites, compiler/loader failures and unavailable dependencies fail the lane.

| Mutation | Required defect that the cases must catch |
| --- | --- |
| expiry_before_receipt | Ignore an old effect/invoke deadline during point verification, allowing late evidence to conceal expiry. |
| false_edge | Stop checking the independently required edge baseline/state fields. |
| refunded_spend | Stop checking complete retained receipt/spent correspondence, allowing a coherently rehashed charge refund. |
| negative_member | Omit a member with no newly emitted proposal when deriving the complete time cell. |
| widened_cell | Accept a rehashed noncanonical cell instead of deriving and comparing its full bounds. |
| cutoff_omission | Omit a complete contributor/domain after the batch cutoff or fail to check its full conflict/decision consequence. |

Each family must catch all six defects through ExUnit.AssertionError failures
with zero runtime, setup, invalid-test or other harness errors and no skipped or
excluded tests. Every result includes exact total/failure/assertion/error counts;
missing, duplicate or malformed markers fail. A mutant can produce any positive
assertion count, but a process/loader error is never a successful catch. The
ordinary extracted run has exactly eight passing cases per family; mutation
runs have exactly seven executed behavioral cases each. A passive identity
check cannot be substituted for a semantic catch.

## Failure, cleanup and evidence

Any failed build, archive inspection, identity assertion, native/public boundary,
oracle assertion, missing result marker or surviving mutation fails the opt-in
lane. There is no partial-green result, fallback to siblings, enlarged limit,
reused mutant build or reduced family/case set. The normal archive gate remains
unchanged when the flag is absent.

The parent owns a try/after cleanup boundary around all archive extraction,
consumer/dependency builds and mutant files. The lane removes that entire owned
workspace on success or failure and records the cleanup result. It creates no
Docker resources. Reusable existing dependency/build/PLT caches and unrelated
user data remain intact. A forced external kill is reported as incomplete and
its exact owned workspace is inspected and cleaned before another run.

Successful execution adds source/command/archive/lock identities and actual
counts to provenance and updates the owning catalogue. This profile is entry
criteria until those checks have run. It does not alone close all VD-T1–T14,
the broad WRO.01–04 contracts, consumer adoption, current authority, installed
clocks, source continuity, containment or physical qualification.

The [archive record](../provenance/decision-archives-2026-10.md) supersedes the
local-only preflight scope for these exact inputs. Both extracted projects pass
all eight cases, including their independent cohort identity and public query
without application startup. Each family catches all six defects through
assertions across seven behavioral cases per mutation, with zero harness errors,
skips or exclusions. The parent joins its two concurrent mutation VMs before
removing the complete owned workspace.

The broader VD-T1–T14 acceptance matrix and owning verifier milestone remain
open. This archive result grants no current consumer authority, installed clock,
host transaction, wider Model/Analysis or physical qualification.
