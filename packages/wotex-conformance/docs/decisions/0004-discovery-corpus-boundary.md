# Decision: reserve a separate Thing Description Directory corpus

## Status

Accepted on 2026-09-14. No Discovery corpus or Discovery conformance claim is
implemented by this decision.

## Context

The W3C Web of Things Discovery Recommendation of 5 December 2023 defines
introduction and exploration mechanisms. Section 7.3.2.1 specifies a RESTful
HTTP Things API for creating, retrieving, updating, deleting, and listing Thing
Descriptions. The existing corpora exercise only Thing Description and Thing
Model document operations under WCF.01 protocol revision 1.0. Reusing either
corpus for directory behavior would mix document-value evidence with stateful
HTTP evidence and would require observation shapes that the current protocol
does not define.

## Decision

A future Discovery corpus will be a separate content-addressed corpus. Its first
proposal is limited to the Things API in Discovery Recommendation sections
7.3.2.1.1 through 7.3.2.1.6. The candidate operation and assertion identifiers
are:

| Candidate operation | Section | Candidate W3C assertion identifiers |
| --- | --- | --- |
| `directory.thing.create_identified` | 7.3.2.1.1 | `tdd-things-create-known-td`, `tdd-things-create-known-td-resp` |
| `directory.thing.create_anonymous` | 7.3.2.1.1 | `tdd-things-create-anonymous-td`, `tdd-things-create-anonymous-id`, `tdd-things-create-anonymous-td-resp` |
| `directory.thing.retrieve` | 7.3.2.1.2 | `tdd-things-retrieve`, `tdd-things-retrieve-resp`, `tdd-things-retrieve-resp-content-type` |
| `directory.thing.replace` | 7.3.2.1.3 | `tdd-things-update`, `tdd-things-update-resp` |
| `directory.thing.merge_patch` | 7.3.2.1.3 | `tdd-things-update-partial`, `tdd-things-update-partial-mergepatch`, `tdd-things-update-partial-contenttype`, `tdd-things-update-partial-partialtd`, `tdd-things-update-partial-resp` |
| `directory.thing.delete` | 7.3.2.1.4 | `tdd-things-delete`, `tdd-things-delete-resp` |
| `directory.thing.list` | 7.3.2.1.5 | `tdd-things-list-method`, `tdd-things-list-resp`, `tdd-things-list-resp-content-type`, `tdd-things-list-pagination-order-default` |

Invalid Thing Description submissions for create, replace, and merge-patch
operations may additionally exercise `tdd-validation-result`,
`tdd-validation-response`, and `tdd-validation-response-utf-8` from section
7.3.2.1.6. An assertion identifier is evidence only when the vector cites its
section and observes the corresponding behavior. The list does not claim that
every requirement in those sections is covered.

The first vector proposal must pair successful and rejected submissions where
the cited requirement defines both behavior classes. It must also cover an
empty list, ordering of at least two identifiers, identified and anonymous
creation, full replacement, member removal through JSON Merge Patch, and
retrieval after each state transition. Optional pagination belongs in a later
corpus revision because a directory may omit it.

The candidate operation names are not valid WCF.01 revision 1.0 operations.
Before adding vectors, a successor specification must define bounded inputs,
normalized observations, errors, state reset, limits, and compatibility for
the operation family. Expected HTTP status, headers, documents, and directory
state remain runner-side material and must not cross the target protocol.

## Consumer fixture obligations

The executable evidence must use an independently implemented external adapter
against one immutable directory artifact or public interface identity. The
consumer fixture must:

- start from deterministic empty state for each vector or use isolated unique
  identifiers and prove cleanup;
- keep the endpoint and any capability outside vectors and reports;
- use fixed clocks for expiry behavior and reserved domains and URNs for
  synthetic Thing Descriptions;
- derive requests and observations from the declared operation and input,
  without reading expectations, vector digests, or provenance;
- verify the subject artifact before opening a connection;
- record pass, mismatch, unsupported, timeout, malformed-response, and
  cross-run isolation outcomes against the exact package archive; and
- record the directory artifact, corpus, target protocol, runtime, and
  dependency cohort needed to reproduce the result.

The conformance library remains passive. It gains no HTTP client, directory
process, persistence layer, credentials, or application callback.

## Evidence profiles and exclusions

The proposed corpus may classify directory semantics with the `directory`
profile. A `live_transport` result requires a separate lane that performs the
HTTP exchange. Evidence from `value`, `codec`, `runtime`, or `binding` profiles
does not substitute for either profile. `hardware`, `certification`, and
`production` profiles remain unsupported.

The proposal excludes introduction mechanisms in section 6, the Events and
Search APIs in sections 7.3.2.2 and 7.3.2.3, security bootstrapping, directory
discovery, authentication policy, authorization policy, external
certification, deployment availability, and performance claims.

## Promotion conditions

No Discovery claim may be added to the catalogue, README, bundled corpus, or
report evidence until all of the following exist in one reviewed change:

1. a revised WCF.01 contract and matching portable schemas for the operation
   inputs and normalized observations;
2. revision-pinned valid, invalid, and boundary vectors with reproducible
   vector and corpus digests;
3. an independent target that passes the claimed vectors without expectation
   material;
4. mismatch, unsupported, infrastructure-failure, lifecycle, and archive-only
   consumer evidence; and
5. documentation that states the exact evidence profile and remaining
   exclusions.

## Consequences

Discovery remains reserved provenance. The current Thing Description and Thing
Model corpus digests and claims are unaffected. A later proposal can implement
the bounded Things API surface without implying support for all Discovery
mechanisms or complete Thing Description Directory conformance.
