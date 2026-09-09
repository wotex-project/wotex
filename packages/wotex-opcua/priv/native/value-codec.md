# Native typed value codec

The C value codec converts the WOP.10/WOP.11 typed value subset between the
package's JSON interprocess representation and open62541 1.5.7 structures.
Its functions perform no network operation and create no client or Session.
Native request admission, secure services, receive-side SDK decoder limits and
callback ownership remain separate implementation requirements.

## Explicit ownership and allocation

`wop_value_read_variant` and `wop_value_read_data_value` accept only a syntax tree
admitted by `wop_json_read`. The caller supplies an aligned `WopValueArena` of at
most 2097152 bytes. Allocation checks capacity and alignment before advancing
its cursor. There is no heap fallback. Retained strings, byte bodies, identifiers,
array elements and dimensions belong to this arena. The parser pool can be
cleared immediately after successful conversion.

The resulting SDK Variant has `UA_VARIANT_DATA_NODELETE`. Its members borrow the
arena until the operation retires. The caller must not apply `UA_clear` to these
members or reset the arena while an SDK operation retains them. A failed read
zeroes the result and rolls back only the allocations made by that call.
`wop_value_arena_reset` overwrites used arena bytes and invalidates all borrowed
values. It does not release resources owned by a pending SDK operation.

The response writers borrow a validated SDK structure for the duration of the
call and copy retained data into a separate bounded yyjson mutable-document
pool. The caller discards the entire partial document after any failure.
Serialized output, its LF delimiter, and the native owner's queued bytes require
separate admission under WOP.13; a successful typed projection alone does not
prove that a complete response fits the 131072-byte frame.

The C status set is finite: `WOP_VALUE_OK`, `WOP_VALUE_INVALID`,
`WOP_VALUE_LIMIT`, and `WOP_VALUE_UNSUPPORTED`. The operation owner assigns the
public error phase and effect according to whether failure occurs before an
SDK call or while validating a response. These primitives cannot establish a
remote effect or choose a retry policy.

## Typed representation

Objects accept exactly their documented fields. Type names come from a fixed
built-in table. Scalars carry `array: false`; arrays carry `array: true` and
retain null versus empty storage. Array elements are flat and number at most
1024. Optional dimensions contain two through eight positive axes with a checked
product equal to the nonempty array length. Each string or ByteString is at
most 65536 bytes. Complete encoded Variants and DataValues are at most 1048576
bytes. Namespace indices are unsigned 16-bit values; numeric identifiers and
status fields are unsigned 32-bit values.

Signed and unsigned 64-bit numbers are parsed exactly from raw JSON number
lexemes. DateTime remains a signed 64-bit count of 100 ns ticks, including
extreme and sub-microsecond values. Floating values must be finite; their signed
zero is retained. GUID text is canonical lowercase. NodeId text carries an
explicit canonical `ns=N;` prefix without leading decimal zeroes. String and
opaque NodeId bodies retain the 4096-byte identity limit.

Nullable strings retain U+0000 as a length-bearing value. ByteString and encoded
ExtensionObject bodies use the exact `{"type":"bytes","base64":"..."}`
envelope or null. Base64 uses the standard padded alphabet with zero unused
bits. The `none`, `binary`, and `xml` ExtensionObject tags retain the encoding
NodeId and uninterpreted body. XML bodies require valid UTF-8; this codec does
not parse XML or instantiate an SDK class from a received type name.

DataValue projection retains `has_value`, status, both timestamps and valid
fraction fields. Missing values omit `value`; a present Null Variant retains it.
Fractions are units of 10 ps within the 100 ns tick. Writers retain fractions
only when the matching timestamp is present and normalize wire fractions above
9999 to 9999, as required by OPC UA Part 6. SDK receive-side decoding and remote
service-status acceptance remain distinct from this pure projection.

## Executable corpus

`fixtures/value-v1.json` contains materialized input JSON frames, operation
names, arena capacities, exact expected status and independently constructed
Part 6 bytes. `value_check --case ABS_CORPUS CASE_ID` selects exactly one case.
CMake creates one CTest per case identifier. The fixture file is a JSON document;
every `input_json` value is separately admitted by the production JSONL reader.

The checker overwrites the parser pool and input copy before SDK binary
encoding. It overwrites the SDK arena before serializing the projected result.
It compares the complete typed result and encoded bytes, checks allocator
rollback on rejected input, and treats a missing case or nonzero native exit as
failure. These cases prove conversion in the pinned SDK build. They do not prove
an independent server interaction, malformed network-frame preallocation bounds,
or native Session and subscription acceptance.

`value_fault_check CASE_ID` exercises SDK structures without relying on the input
constructor to produce malformed data. Its finite case table is:

| Case | Assertion |
| --- | --- |
| WOP-NF01 | Invalid arena and output parameters fail without allocation. |
| WOP-NF02 | A failed read retains preexisting arena bytes, clears new bytes and restores its checkpoint. |
| WOP-NF03 | Invalid writer parameters and types outside the fixed table return no projected value. |
| WOP-NF04 | Excessive array counts and inconsistent storage fail before accessing element memory. |
| WOP-NF05 | Invalid dimensions, products and missing dimension storage are rejected. |
| WOP-NF06 | SDK non-finite floating values fail before JSON serialization. |
| WOP-NF07 | Excessive strings and byte bodies fail before accessing declared payload memory. |
| WOP-NF08 | Overlong, surrogate, excessive and truncated UTF-8 encodings fail. |
| WOP-NF09 | Namespace URI and concrete namespace conflicts fail. |
| WOP-NF10 | Unsupported decoded ExtensionObjects and invalid XML byte bodies return no projected value. |
| WOP-NF11 | DataValue presence flags control fields; orphan fractions are omitted and excessive fractions normalize to 9999. |
| WOP-NF12 | Writer-pool exhaustion returns no result and leaves the borrowed SDK value intact. |
| WOP-NF13 | All 1024 byte-array elements pass both typed directions and retain the exact encoded length. |
| WOP-NF14 | A 65536-byte string passes both directions; 65537 bytes fail with complete arena rollback. |
| WOP-NF15 | A 65536-byte body retains every byte through Base64 serialization, strict parsing and SDK construction. |
| WOP-NF16 | An exactly 1 MiB SDK Variant projects successfully; one additional wire byte fails without changing borrowed values. |

The value definitions follow [OPC UA Part 6 1.05.07 Variant](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.16)
and [DataValue](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.17).
The SDK structure and allocator API are those of the pinned open62541 source.
