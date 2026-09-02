# Decision 0001: caller-owned numerical execution

## Decision

`wotex_nx` is a normal library. Loading it starts no process. It does not own a
model, backend, scheduler, clock, registry, queue, database, or supervision
tree. It creates deterministic values and lazy `Nx.Batch` containers from
explicit inputs. A consumer decides if, where, and when any numerical program
runs.

## Consequences

- Package dependency does not mutate runtime topology.
- Tests can prove conversion semantics without an application host.
- Backend and model ecosystems remain replaceable.
- Numerical results have no authority until a consumer admits them.
