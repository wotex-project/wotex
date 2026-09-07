# WCT.01 — Manifest, compatibility, execution context, and capability values

Status: Accepted

Specification version: 1.0.0

Wire schema version: 1.0.0

Owner: `wotex-continuum`

## 1. Purpose

WCT.01 defines inert values through which a producer declares what an artifact
can do, where it can execute, and what it requires from a consumer host. The
contract supports discovery and admission input; it does not perform admission,
activation, entitlement, provider selection, or policy evaluation.

The key words MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are to be
interpreted as described by
[BCP 14](https://www.rfc-editor.org/rfc/rfc2119) when, and only when, they appear
in all capitals.

## 2. Standards relationship

The meanings of Thing, Thing Description, Property, Action, Event, Consumer,
Exposer, interaction affordance, Form, and DataSchema come from:

- W3C Recommendation, *Web of Things (WoT) Thing Description 1.1*,
  5 December 2023, sections 3–5:
  <https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/>; and
- W3C Recommendation, *Web of Things (WoT) Architecture 1.1*,
  5 December 2023, sections 5–7:
  <https://www.w3.org/TR/2023/REC-wot-architecture11-20231205/>.

All fields in this specification are Wotex Continuum fields. They are not Thing
Description vocabulary terms and MUST NOT be inserted into a Thing Description
without an independently defined extension vocabulary.

## 3. Common encoded-form rules

Every top-level value MUST be a JSON object with:

| Member | Requirement |
|---|---|
| `kind` | exact discriminator registered by this specification |
| `schema_version` | exact semantic version of the encoded contract |

Object member names use lower snake case. Unknown top-level members MUST be
rejected. Extension data belongs only in the explicit `extensions` object.
Each extension key MUST be an absolute IRI and each value MUST be a JSON value.

Implementations MUST accept only finite JSON numbers. Duplicate members, an
atom/string key collision in native input, invalid UTF-8, or a configured
resource-limit breach MUST return a typed error.

This includes native JSON object keys nested in payloads, failure details,
quality and extensions. Invalid key bytes MUST produce `invalid_utf8` at the
containing object's path; error paths MUST NOT copy invalid key bytes. Valid
Unicode keys (including empty JSON member names) retain their bytes. Correcting
admission of invalid UTF-8 is a compatible implementation repair, not a wire
schema change: invalid UTF-8 was already outside the accepted JSON contract.

Typed values are not a validation bypass. Constructors and the public encoder
MUST revalidate struct fields, including nested values, and MUST reject a
tampered or manually assembled struct with the same typed error returned for
equivalent invalid map input. Public keyword options MUST be unique and known.

Canonical encoding sorts object keys by UTF-8 byte order, retains list order,
emits no insignificant whitespace, and uses the JSON scalar representation of
the package's supported JSON encoder. This is the WCT project-canonical form;
it is not a claim of RFC 8785 conformance.

Every value module exposes `from_map/1` as the documented constructor for
map-shaped input and `to_map/1` for the wire projection. `new/1` remains an
alias of `from_map/1`; the name `new/1` carries keyword configuration only in
`WotexContinuum.Limits`. A constructor accepts an already accepted struct and
revalidates it rather than trusting it.

## 4. Error contract

An expected failure returns `{:error, %WotexContinuum.Error{}}`. The struct
carries:

| Field | Meaning |
|---|---|
| `code` | stable atom naming the failure |
| `phase` | stage that produced it: `decode`, `validation`, `encode`, `lifecycle`, `compatibility`, or `limits` |
| `path` | RFC 6901 JSON Pointer string rooted at `/`, or `nil` when no wire location applies |
| `message` | human-readable text, not a matching interface |
| `details` | structured, JSON-compatible context |

A path addresses the exact wire location, so `/extensions/urn:example:payload/0`
names list element `0` of extension key `urn:example:payload`. Segments escape
`~` as `~0` and `/` as `~1`, as
[RFC 6901](https://www.rfc-editor.org/rfc/rfc6901) requires. Nested values are
re-rooted under their parent pointer, so a failure inside a nested value keeps
the complete path from the top-level value. `nil` is used only where no wire
member exists, such as an unknown or duplicated keyword option.

Consumers MUST match on `code`, `phase`, and `path`. Message text and the
membership of `details` MAY change in a compatible release.

## 5. `continuum_manifest`

| Member | Type | Rules |
|---|---|---|
| `manifest_id` | string | REQUIRED, non-empty, at most 512 bytes |
| `artifact` | object | REQUIRED `name`, semantic `version`, and `sha256:` digest |
| `compatibility` | `compatibility` object | REQUIRED |
| `supported_modes` | array | REQUIRED, non-empty, unique WCT.03 deployments |
| `capabilities` | array | REQUIRED, unique capability IDs |
| `extensions` | object | OPTIONAL, defaults to `{}` |

An artifact digest is lowercase hexadecimal and covers the immutable artifact
identified by the manifest. The manifest does not establish that the artifact
is trusted; a consumer host verifies digest, origin, signature, and policy.

## 6. `compatibility`

| Member | Type | Rules |
|---|---|---|
| `schema_requirement` | semantic-version requirement | REQUIRED |
| `required_capabilities` | array of requirements | OPTIONAL |
| `extensions` | object | OPTIONAL |

A capability requirement contains a non-empty `id` and semantic-version
`version_requirement`. Evaluation is deterministic: schema version MUST match
`schema_requirement`; every required capability MUST be present exactly once
and its declared version MUST match. Evaluation returns all mismatches and has
no activation side effect.

## 7. `execution_context`

| Member | Type | Rules |
|---|---|---|
| `execution_id` | string | REQUIRED |
| `node_id` | string | REQUIRED; opaque consumer-host node reference |
| `mode` | WCT.03 `mode` | REQUIRED |
| `observed_at` | RFC 3339 timestamp | REQUIRED; normalized to UTC |
| `extensions` | object | OPTIONAL |

Context describes the environment in which another value was observed or
produced. It MUST NOT contain credentials and MUST NOT be interpreted as proof
of identity, authority, or time correctness.

## 8. `capability`

| Member | Type | Rules |
|---|---|---|
| `id` | string | REQUIRED, stable and unique in one manifest |
| `version` | semantic version | REQUIRED |
| `operations` | array of strings | REQUIRED, unique, may be empty |
| `modes` | array of WCT.03 deployments | REQUIRED, non-empty, unique |
| `network` | enum | REQUIRED: `none`, `local`, or `external` |
| `degradation` | enum | REQUIRED: `fail_closed`, `read_only`, `queue`, or `unavailable` |
| `extensions` | object | OPTIONAL |

An operation name is a declared mechanical ability, never authorization. A
consumer host MUST evaluate policy and the current Thing Description before
using an operation that interacts with a Thing.

## 9. Compatibility

Adding an optional extension entry is compatible. Adding an enum member or
optional field requires a schema-minor release and a vector. Removing or
renaming a member, changing canonical bytes, tightening previously accepted
input, or changing a field's meaning is incompatible and requires a new schema
major version.

## 10. Executable evidence

Normative JSON Schema: `priv/schemas/wct-01.schema.json`.

Valid vectors: `test/vectors/valid/wct-01-*.json`.

Invalid vectors: `test/vectors/invalid/wct-01-*.json`.

Canonical vectors: `test/vectors/canonical/wct-01-*.json`.
