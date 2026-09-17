# 0002: Formal evidence belongs between proposals and consumer decisions

Status: accepted. Date: 2026-09-07.

Maude is useful when multiple control rules and delivery orders can lead to
unsafe modeled states. It is unnecessary for tensor construction, numerical
execution, ordinary process supervision or a first working example.

The `ex_maude` profile therefore explores finite simulated control transitions
and produces scoped evidence or replayable counterexamples. It uses an explicit
pool and separately provisioned binary. It is not a dependency of core, Runtime,
Nx or the Lab base graph. No verifier result grants Action authority.

A successful bounded search with zero solutions is inconclusive unless complete
exhaustion is proven for the exact finite model. This prevents a depth limit
from masquerading as verification. Discretization, units, model versions and
lost information are public experiment inputs. Counterexample replay connects
formal evidence to an inspectable simulator without claiming physical safety.

The profile is required programme work and optional runtime activation. WLB.09
owns its concrete model, resource, failure, isolation and distribution criteria.
