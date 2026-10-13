# Paired composition archive consumer profile

Version: 0.1.0. Updated: 2026-10-13. Accepted software acceptance profile;
two isolated consumers pass against the cohort recorded in
[provenance](../provenance/composition-archive-cohort.md).

This profile executes WRO.02 composition and WRO.04 correspondence through two
fresh independent Mix consumers of the same exact extracted archive cohort.
It implements part of R6 in the owning completion contract. Neither consumer
imports another consumer's modules or shares its private state or policy.

The first consumer uses original-source AST references and a private retained
run to compare finite manual composition traces through the public Compiler and
Kernel. The corpus covers Boolean absolute output, scalar/absent predicate
inputs, staged completion, sequence, parallel, waits/delays, child invocation,+cancellation, clock changes and removed definitions. Reference code belongs to
the acceptance harness and is absent from the producer archive.

The second consumer explicitly starts its own bounded journal owner and applies
public transitions under an independently supplied consumer revision/policy.
Its compare-and-commit checks the exact prior original/busy/edge plus its current
snapshot/time. Race a held receipt and policy/resource revision against a
previously prepared transition: stale commit refuses, retained spend survives,
and no transport occurs. It also exercises whole-provided-set conflict before a
one-group cutoff through public Collection/Arbitration. This instrumented
journal demonstrates consumer ownership; it does not qualify a production
transaction engine, authentication, restart/backup or physical execution.

`bin/check_archive.exs --composition-consumers` builds core, Continuum and
routines archives with WOTEX_PATH_DEPS unset, validates archive contents,
extracts them into a disposable directory, and compiles/tests each fresh
consumer separately in production dependency mode. Each checks loaded BEAM
locations under its own build and passive library application metadata. Report
archive, consumer source and lock digests with the exact toolchain/source cohort.
No repository checkout path can substitute for an extracted dependency.
The optional occurrence-archive lane remains separately selectable; ordinary
composition adoption needs no unreleased calendar producer.

Success is a passing independent-source trace consumer and a passing private
journal/arbitration consumer against that same cohort. Dependency/load errors,
missing/changed vectors, stale commit success, refunded spend, a chosen conflict
winner or disagreement with the AST reference falsify this profile. Full model
projection, additional independent semantic profiles and real consumer-host
fault evidence remain separate completion obligations.
