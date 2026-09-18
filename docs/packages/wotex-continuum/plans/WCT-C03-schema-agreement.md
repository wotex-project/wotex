# WCT-C03 schema agreement map

This document indexes agreement between the three normative JSON Schemas,
native constructors, struct reconstruction, encoded admission, canonical bytes,
and published vectors. It is verification evidence, not a fourth normative
specification. WCT.01, WCT.02, and WCT.03 remain the owners of field meaning.

## Agreement rule

Every registered kind has a valid vector, a canonical vector, and at least one
invalid vector. `schema_agreement_test.exs` checks each valid kind through:

1. its owning embedded schema;
2. `from_map/1`, `new/1`, and the `WotexContinuum` facade;
3. reconstruction of the accepted struct;
4. `to_map/1` and schema validation of the projected map;
5. ordinary encoding, canonical encoding, and decoding; and
6. the exact published canonical bytes.

Native top-level constructors may default absent `kind` and `schema_version`.
Encoded top-level input must supply both. Registered values nested below a
top-level envelope may omit their own envelope members; if supplied, those
members must be exact. Projection and canonical encoding restore the complete
nested envelope. This distinction is tested for every registered parent/child
route.

## Registered-kind vector matrix

| Owner | Kind | Structural or format rejection | Semantic rejection where applicable |
| --- | --- | --- | --- |
| WCT.01 | `continuum_manifest` | invalid artifact digest at `/artifact/digest` | capability mode outside `supported_modes` at `/capabilities` |
| WCT.01 | `compatibility` | required/closed fields in the generated matrix | invalid nested version requirement at `/required_capabilities/0/version_requirement` |
| WCT.01 | `execution_scope` | invalid RFC 3339 time at `/observed_at` | none in a static scope value |
| WCT.01 | `capability` | unknown member and invalid semantic version | none beyond member-level validation |
| WCT.02 | `observation_proposal` | non-object quality at `/quality` | native/source admission distinctions remain WCT-C02 evidence |
| WCT.02 | `action_intent` | relative Thing IRI at `/thing_id` | native/source admission distinctions remain WCT-C02 evidence |
| WCT.02 | `action_result` | failed status without `error` at `/status` | completion before start at `/completed_at` |
| WCT.02 | `evidence_reference` | relative evidence IRI at `/uri` | no dereference or authenticity rule belongs here |
| WCT.02 | `delivery` | unregistered `item_kind` at `/item_kind` | acknowledgement before emission at `/acknowledged_at` |
| WCT.03 | `mode` | connected air-gap mode at `/connectivity` | no deployment effect belongs here |
| WCT.03 | `lifecycle` | invalid RFC 3339 time at `/changed_at` | graph edges and generation changes belong to `transition/4` |
| WCT.03 | `degradation` | reduced state with empty detail lists at `/level` | none beyond static state coherence |
| WCT.03 | `exit_receipt` | completed removal with residuals at `/status` | completion before request at `/completed_at` |

Every invalid vector records the expected constructor `code`, `phase`, and
exact RFC 6901 path. Its `schema` classification is `reject` when the owning
schema can express the rule and `semantic` when it cannot. The vector suite
checks the same error through the module constructor, its alias, the facade,
and encoded admission.

## Nested owner matrix

The agreement test injects an invalid child field, a forged child struct, and
an invalid extension property name through each safe path below. Registered
children also exercise optional nested envelope reconstruction.

| Child | Owning path or paths |
| --- | --- |
| `Artifact` | `continuum_manifest.artifact` |
| `Compatibility` | `continuum_manifest.compatibility` |
| `CapabilityRequirement` | `compatibility.required_capabilities[]`, `continuum_manifest.compatibility.required_capabilities[]` |
| `Capability` | `continuum_manifest.capabilities[]` |
| `Mode` | `execution_scope.mode` and the three WCT.02 `context.mode` paths |
| `ExecutionScope` | `observation_proposal.context`, `action_intent.context`, `action_result.context` |
| `EvidenceReference` | observation, intent, result, and degradation `evidence[]`; exit `artifacts[]` |
| `Failure` | action result, delivery, and exit `error` |

The parent constructor, facade, encoder, and canonical encoder must return the
same safe child path for a forged nested struct. Invalid extension keys use the
containing `extensions` path and never introduce untrusted bytes into an error
path.

## Schema assertions and semantic checks

The dependency-free agreement checker evaluates every assertion keyword used
by the bundled schemas, including `format`, `propertyNames`, conditional state
rules, and collection cardinality. WCT treats `uri` and `date-time` formats as
assertions for this evidence. Consumers using another Draft 2020-12 validator
must enable format assertion or retain the constructors as the admission
boundary. Cross-document references use the target schema's absolute `$id`, so
resolution does not depend on a checkout directory or filename convention.

These checks intentionally remain in constructors because the schemas do not
express them:

- Elixir semantic-version requirement grammar;
- byte-count maxima where JSON Schema `maxLength` counts characters;
- uniqueness by `id` within an array of objects;
- subset relationships such as capability modes within manifest modes;
- ordering between two timestamps; and
- lifecycle transition history and generation increments.

Schema acceptance is therefore necessary but not sufficient for admission.
The matrix forbids the opposite mismatch: a constructor-accepted projected
value must validate against its owning schema. The semantic invalid vectors
make each deliberate schema over-acceptance visible.

## Compatibility classification

WCT-C03 is a compatible contract repair. The schemas now admit members already
declared optional and reject state combinations, unregistered delivery kinds,
and malformed semantic versions that constructors and normative text already
rejected. Constructors now reject a non-current `2.x` envelope version that the
schema's exact `2.0.0` identity never admitted. Accepted values, field meaning,
and canonical vectors do not change. Embedded schema digests do change.

This evidence adds no schema-validation API and no host authority. Runtime
schema selection, artifact trust, identity, authorization, persistence,
dispatch, transition serialization, and independent archive consumption remain
outside the package. Archive-consumer proof is WCT-C04 work.
