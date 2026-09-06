# Wotex Directory completion contract

Plan `WTD-C`, revision `1.0.0`. This is an immutable work-definition baseline,
not a progress report. Preserve work IDs and accepted evidence requirements;
change scope through an explicitly versioned successor. Implementation status
in the catalogue describes WTD.01's bounded implementation, not release readiness.

## Ownership and implementation boundary

WTD.01 and decisions 0001/0002 own the implementation contract. The package owns
storage-neutral directory operations, immutable registration/query/page/event
values and explicit repository, authorization, identifier and clock ports.
The consumer owns storage, atomicity, authorization policy, credentials, servers,
scheduling, retention execution and durable publication. No Application callback,
database, migration, implicit retry or hidden expiry worker is permitted.

The public operation inventory is `Wotex.Directory.register/3,4`, `get/3`,
`replace/4,5`, `patch/4,5`, `delete/3,4`, `list/2,3`, `query/3`, `expire/2,3`
and `introduction/1`; their values and error codes remain WTD.01 sections 5–8.
New proof work must exercise this surface rather than importing private modules.
Introduction has no repository or authorization side effect. All other access
must preserve authorization-before-storage and context isolation. Patch admission
precedes writes; expected-version conflicts never silently retry. A consumer port
must atomically check the version and apply the mutation. A failed mutation must
not emit a successful mutation/event value.

Expiry is explicit, bounded and idempotent. Retention advances an active entry
once; purge removes eligible entries. Listing revision binds membership, including
time-driven expiry, not merely a database update counter. A changed collection
invalidates continuation. Unicode ordering, clock-regression handling, registration
precedence and retrieval-only enrichment must remain unchanged. The library owns
no processes to restart or stop: recovery and durable event delivery belong to
the consumer. Port errors must not expose credentials, raw payloads or principals.

## Standards and remaining claims

| Authority | Exact implemented claim | Remaining or explicitly excluded claim |
| --- | --- | --- |
| WoT Discovery Recommendation 2023-12-05 | WTD.01 registration, listing, introduction and explicit expiry mechanics | Full Discovery conformance, transport endpoints, RDF and query languages are not claimed |
| TD 1.1 Recommendation 2023-12-05 | Public core TD validation and directory enrichment | No independent TD parser or stronger validation claim than the core |
| RFC 7396 | Bounded JSON merge patch followed by validation | Not JSON Patch or unrestricted arbitrary allocation |
| RFC 3339 / RFC 8288 | Registration time and next-link metadata specified in WTD.01 | Consumer wire serialization and HTTP behavior require separate evidence |

`docs/provenance/w3c-sources.md` records primary sources. Do not add standards
claims from a passing unit test alone. The remaining claim ledger is:

- `WTD-CL01`: repository portability under contention requires a second,
  independently implemented consumer repository contract test.
- `WTD-CL02`: archive-only consumption requires the actual release archive and
  dependency cohort, not a path dependency test.
- `WTD-CL03`: HTTP/SSE/search/certification remain outside this plan; no work item
  silently promises them. Event values do not prove durable or wire delivery.
- `WTD-CL04`: explicit batch/page/patch limits do not prove a global memory or
  latency ceiling for arbitrary consumer ports.

| Claim dimension | Current status | Promotion evidence |
| --- | --- | --- |
| Value support | Directory context, entry, page, patch, revision and Event values are covered by WTD.01 evidence | C01/C02 close malformed, temporal and concurrency boundaries |
| Operation support | Register/get/list/replace/patch/delete/expire mechanics only | Port-contract vectors for every success, denial, conflict and rollback |
| Independent interoperability | Not established | C04 second consumer repository against the exact archive |
| Profile conformance | Not established; no Discovery search/HTTP profile claim | Separately accepted revision-pinned profile corpus |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Work packages

| ID | Prerequisites | Exact deliverable | Executable acceptance |
| --- | --- | --- | --- |
| WTD-C01 | WTD.01 | Reusable public-port contract tests for fetch/insert/replace/delete/list/expire_due; no production storage implementation | Two independent consumer adapters pass authorization ordering, tenant/context isolation, atomic conflict, expiry and collection-revision tests |
| WTD-C02 | WTD-C01 | Deterministic concurrent mutation and interrupted-consumer scenarios | Competing expected-version writes have one winner; failure has no successful mutation; repeat expiry makes no second transition; resumed paging detects expiry-only membership changes |
| WTD-C03 | WTD.01 | Archive-only minimal consumer fixture using no source checkout and no implicit application startup | Build archive, unpack into isolated dependency directory, compile with warnings as errors and run register/get/patch/list/expire plus invalid/conflict cases through public API |
| WTD-C04 | WTD-C01, WTD-C03 | Independent reference consumer with explicit repository/auth/clock/ID implementations | All public operations and context separation pass against the exact archive digest; consumer tests prove atomicity rather than assuming it |
| WTD-C05 | WTD-C02, WTD-C04 | Bounded claim-to-test matrix, compatibility review and release evidence manifest | Every claimed clause has a positive and applicable negative test; no unsupported search/transport claim; gate inputs are complete and internally consistent |
| WTD-C06 | None | Allowlisted package documentation inputs that exclude machine-local progress records | `mix hex.build` archive listing proves docs/tasks/local and all contained files absent even when a sentinel exists locally |

C01 and C03 can proceed independently. C02 must not invent a database product;
its adapters are test consumers. No new repository or public operation is
authorized by this plan. Public signature, port, expiry or error changes require
a WTD.01 compatibility decision before implementation.

## Gate definitions

Each gate records the exact source commit, dependency lock/cohort, runtime,
commands and outcomes; archive gates additionally bind archive SHA-256. Reusing
evidence after a relevant change requires rerunning affected gates.

- `repository_green`: format, warnings-as-errors compilation, the entire package
  test suite, strict Credo, docs and `git diff --check` pass with the declared
  supported runtime. Existing tests under `test/wotex/directory/` are the starting
  evidence, not a substitute for C01/C02.
- `archive_consumer_green`: C03 passes against an unpacked `mix package` archive;
  inspect metadata/dependencies, no Application callback, private/local files or
  sibling checkout dependencies. The path-dependency development mode is forbidden
  as archive proof.
- `reference_consumer_green`: C01/C02/C04 pass with an independently implemented
  repository, frozen clock and deliberately failing ports using the same archive.
- `public_release_candidate`: the preceding gates, C05 and provenance/license/
  package review pass. This gate authorizes no push, tag or publication.
- `stable_api_candidate`: release-candidate evidence plus complete public-value,
  port, error and temporal compatibility review; no unresolved advertised claim
  or undocumented breaking behavior. It is not W3C certification.

## Local execution records

The only mutable completion tracker path is
`docs/tasks/local/wotex-directory-tracker.yaml`, ignored by Git. Package inputs
allowlist publishable documentation and structurally exclude that path; every
candidate archive must still prove WTD-C06 because `.gitignore` does not govern
a Hex archive.
Its schema is `schema_version: "1.0.0"`, `plan_id: WTD-C`, `plan_revision: "1.0.0"`,
and `work_items`, each with `id`, `state` (`queued|active|blocked|verified`),
`prerequisites`, `evidence` (source_commit, archive_sha256 when relevant,
dependency_cohort, runtime, command, exit_code) and `remaining_claims`.
Use explicit null for unavailable evidence; never equate a checked task with a
release gate. Plans/catalogues contain no rolling completion state.
