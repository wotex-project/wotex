# WCT-C02 admission boundary map

This document maps the native-value and encoded-source safety boundary to
executable evidence. WCT.01 remains the normative owner of common admission,
error, limit, and canonicalization rules; WCT.02 and WCT.03 own the fields that
carry the tested JSON values. This map adds no host policy or mutable runtime.

## Native UTF-8 parity

Native JSON values admit only valid UTF-8 strings and object keys. An invalid
string value returns `invalid_utf8` at its exact safe path. An invalid object
key returns `invalid_utf8` at the containing object's path, so malformed bytes
are never copied into `WotexContinuum.Error.path`.

`test/wotex_continuum/admission_parity_test.exs` executes four invalid byte
classes—isolated continuation, overlong sequence, surrogate encoding, and
truncated multibyte sequence—as both a nested object key and a nested value at
every JSON payload route:

| Route | Safe key path | Safe value path |
| --- | --- | --- |
| `observation_proposal.value` | `/value/safe` | `/value/safe/0` |
| `observation_proposal.quality` | `/quality/safe` | `/quality/safe/0` |
| `action_intent.input` | `/input/safe` | `/input/safe/0` |
| `action_result.output` | `/output/safe` | `/output/safe/0` |
| direct `Failure.details` | `/details/safe` | `/details/safe/0` |
| `action_result.error.details` | `/error/details/safe` | `/error/details/safe/0` |
| `delivery.error.details` | `/error/details/safe` | `/error/details/safe/0` |
| `exit_receipt.error.details` | `/error/details/safe` | `/error/details/safe/0` |

Each registered owner is tested through `from_map/1`, `new/1`, reconstruction
of a forged struct, `WotexContinuum.to_map/1`, regular encoding, and canonical
encoding. The nested failure constructor is tested directly and through each
of its three owners. A valid matrix containing non-ASCII strings, combining
characters, non-BMP characters, and an empty object key proves that rejection
does not narrow valid Unicode.

`CanonicalJSON.encode/1` also validates every object key before sorting it or
constructing a child pointer. Direct maps with malformed keys therefore fail
at the safe parent path with encode phase, matching the path-safety guarantee
provided by typed reconstruction.

## Resource-bound split

The library intentionally distinguishes a caller-owned native term from an
untrusted encoded source:

| Control | Native constructor | `Codec.decode/2` encoded source |
| --- | --- | --- |
| JSON structural depth | Fixed `Limits.max_depth/0`, measured from the payload handed to the field validator | Configured `max_depth`, measured over the encoded document |
| UTF-8 keys and values | Recursively validated, with safe JSON Pointer paths | Checked by the core decoder before continuum construction |
| JSON number/value form | Integers, finite BEAM floats, booleans, null, valid strings, lists, and string-keyed maps | JSON lexical and decoded-value admission by the core decoder |
| Source bytes | Not applicable to an already resident term | `max_bytes`, measured on iodata before flattening |
| Node count | No constructor option | `max_nodes`, checked after bounded decoding |
| Collection size | No constructor option | `max_collection_size`, checked after bounded decoding |
| String bytes | Field-specific semantic bounds still apply; no general payload limit option | `max_string_bytes`, lexically scanned before allocation-heavy decoding |

The distinction is deliberate. Applying encoded-source limits to a native term
would require a separate traversal and policy API; the value constructors do
not claim to own that consumer decision. Consumers accepting large native terms
apply their own byte, node, collection, and string policy before calling a
constructor.

The executable split test first admits the same payload natively, then encodes
it and proves that configured string, collection, and node limits return
`limit_exceeded` in phase `limits` with the exact core cause retained under
`details.core_code`. The shared depth test proves the fixed native boundary and
the decoder boundary independently. Native unsupported terms return
`invalid_json_value`; finite floats remain admitted.

## Decoder preflight and allocation statement

For iodata, `Codec.decode/2` calls `:erlang.iolist_size/1` before
`IO.iodata_to_binary/1`. An over-limit source returns
`details.core_code == :byte_limit_exceeded` without allocating the flattened
copy. This does not reclaim or bound the caller's already resident iodata. An
admitted source may allocate one flattened binary up to `max_bytes` before core
admission copies accepted decoded strings away from that source.

The preflight regression combines over-limit iodata with malformed UTF-8 and
proves that the byte error wins with exact measured and configured sizes.
Separate malformed-JSON inputs containing an oversized string or excess depth
prove that the lexical string/depth controls win before allocation-heavy JSON
decoding. Collection and node controls remain post-decode structural checks,
as documented by WCT.01.

These tests establish observable error ordering and the implementation's
pre-flatten call order. They do not claim to measure total BEAM memory, bound
caller allocations, or constrain memory retained after an accepted value is
returned.

## Deliberate boundary

Admission remains synchronous pure validation. No process, queue, storage,
network client, credential, identity decision, authorization rule, retry, or
reconciliation behavior is introduced. The
[WCT-C03 schema agreement map](WCT-C03-schema-agreement.md) layers schema and
vector agreement on these admission rules. Independent archive consumption is
separate WCT-C04 work.
