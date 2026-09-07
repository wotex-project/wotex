# 0001: An independent consumer laboratory with an Nx entry point

Status: accepted. Date: 2026-09-07.

The sibling libraries expose narrow public ports and completion contracts that
need external consumers. We retain those boundaries and put runnable composition
in Lab. No foundational library can depend on Lab. Lab follows their package
namespace, numbered specs, catalogue, completion contract, explicit inputs,
structured errors, public documentation and local quality gates.

The base graph contains `wotex`, `wotex_nx` and `nx`. A deterministic thermal
experiment gives Nx users a useful first result. Heavy network, serving,
training, dashboard and formal dependencies belong to explicit host integration
profiles in this repository. Their implementation is required by the programme;
activation is optional for consumers. There is no new forest of adapter repos.

Lab has no application callback. Ordinary caller-supplied child specs own
instance lifetimes. Anonymous child supervisors and caller-chosen names avoid
a global Registry or auto-discovered components. A Scenario is data, not code.
An explicit host owns process selection, state, artifacts, credentials and
effects. The small foundation exports working primitives and one working
consumer example; unimplemented integrations get specifications, not stubs.

The original proposal's breadth is retained but priority tiers and deferred
milestones are replaced by a dependency-aware completion contract. Nx is a
primary adoption route with Serving, Axon, reproducible datasets and baseline
comparisons. SQLite uses Exqlite directly to keep its independent transactional
algorithm inspectable. HTTP/MQTT authenticated reconnect re-enters Runtime
because the inspected ports prohibit credential retention.

Three statuses prevent source coverage being confused with independent evidence
or artifact adoption. Local paths are an explicit dev/test/docs mode, matching
the other libraries. Candidate/released modes reject them. Hex availability is
checked independently and never inferred from a README installation example.
