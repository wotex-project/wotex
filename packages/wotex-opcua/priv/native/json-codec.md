# Native JSON codec contract

This WOP-X03 implementation contract admits yyjson 0.12.0 for the C process
boundary. The syntax and number reader has executable corpus tests. Typed SDK
construction and serialization are implemented for the admitted typed subset;
the executable now admits secure open, one-at-a-time Value read and close.
Other services and complete output buffering remain required. This format is the
package's typed interprocess protocol, not OPC UA JSON wire encoding.

## Source identity and license

The reviewed upstream is [yyjson 0.12.0](https://github.com/ibireme/yyjson/releases/tag/0.12.0),
commit `8b4a38dc994a110abaec8a400615567bd996105f`. Its source archive is
`https://codeload.github.com/ibireme/yyjson/tar.gz/refs/tags/0.12.0`, SHA-256
`b16246f617b2a136c78d73e5e2647c6f1de1313e46678062985bdcf1f40bb75d`.
The package vendors these unmodified files and their MIT notice:

| Upstream path | Bytes | SHA-256 |
| --- | ---: | --- |
| `src/yyjson.c` | 410813 | `ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a` |
| `src/yyjson.h` | 322407 | `175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3` |
| `LICENSE` | 1084 | `45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947` |

Source and file digests enter the native build identity. Local policy lives in
the package adapter, with no undocumented upstream edit. Build output retains
the upstream copyright and permission notice.

## Strict syntax and bounded allocation

Compile with `YYJSON_DISABLE_NON_STANDARD=1`, `YYJSON_DISABLE_UTILS=1` and
`YYJSON_DISABLE_INCR_READER=1`, `YYJSON_DISABLE_FAST_FP_CONV=0` and
`YYJSON_DISABLE_UTF8_VALIDATION=0`. Parse a complete LF-delimited frame body using
`yyjson_read_opts` with exactly `YYJSON_READ_NUMBER_AS_RAW`. Never enable
`STOP_WHEN_DONE`, in-situ input mutation, JSON5, invalid-Unicode acceptance,
comments, trailing commas, Inf/NaN or extended number/string/whitespace flags.
The input including LF is at most 131072 bytes. The framing owner rejects NUL
and unescaped LF outside the final delimiter; escaped U+0000 in a JSON string
remains a length-bearing string value.

Each parse owns a fixed 2097152-byte allocator pool initialized with
`yyjson_alc_pool_init`; it has no heap fallback. Parser allocation exhaustion
fails closed. The pinned parser's documented worst-case read bound is
`13 * body_bytes + 256`, below this pool for a maximum frame. The pool is
released/reset before another request is parsed. An independent writer pool is
also at most 2097152 bytes, with no heap fallback. Encoded output is admitted
only when its complete byte count including LF fits the same frame ceiling.
These two pools do not include separately bounded SDK values or frame queues.

Validate the parsed syntax tree before allocating SDK values. Root depth is
one; every nested array or object increments container depth, at most eight.
A scalar child does not add container depth. Every value, including the root,
counts as one node; object keys do not count as value nodes. Maximum total is
4096 nodes. Each array has at most 1024 elements and each object at most 1024
key/value pairs. Validation uses a fixed depth-eight traversal stack, not a
recursion depth controlled by input. The parser itself uses its fixed pool even
when rejected syntax exceeds these semantic limits.

Object keys are compared by decoded byte length and bytes, including embedded
NUL. Any duplicate decoded key fails, including escaped aliases. Duplicate
checking occurs before operation field lookup. Each operation then accepts only
its exact key set and scalar types. Unknown fields do not pass through to an SDK
configuration or dynamically select a class, function or type.

## Exact numbers and typed bytes

All number tokens remain raw until the selected field's type is known. Their
maximum token length is 128 bytes. Integer fields accept only an optional minus
sign and decimal digits, with checked magnitude accumulation; a decimal point
or exponent does not satisfy an integer field. Signed values retain the full
`-9223372036854775808..9223372036854775807` range. Unsigned values retain
`0..18446744073709551615`; mathematical negative zero is zero, while any negative
nonzero magnitude fails. A Boolean is never a number. Field-specific narrower
widths apply before assigning an SDK member. DateTime ticks, generations and
correlation counters never pass through `double` or calendar conversion.

Float and Double use their explicit IEEE-754 widths and a C numeric locale.
Reject non-finite and overflowing conversion. Preserve the negative-zero sign
bit; serialization emits `-0.0`, never integer zero. Integers serialize as exact
decimal digits. Strings and object keys use explicit byte lengths; no `strlen`
or NUL-terminated comparison may discard their suffix. Typed byte payloads use
the exact C07 base64 envelope, canonical alphabet and padding; decoded length
is checked against the selected type before allocation.

## Executable acceptance

The native codec test must execute strict syntax, duplicate/escaped-key,
depth/node/container, maximum frame, allocator exhaustion and length-bearing
NUL cases. Numeric cases include signed/unsigned endpoints, one beyond each
endpoint, exponent/fraction lookalikes for integers, signed zero at both float
widths, non-finite/overflow rejection and exact one-tick DateTime differences.
Valid output is compared byte-for-byte where canonical representation is part
of the contract, and decoded SDK fields are compared independently. Failure
leaves no live document, SDK allocation or emitted success frame. Normal,
AddressSanitizer/UndefinedBehaviorSanitizer and LeakSanitizer lanes execute the
same malformed corpus; parser presence or a successful build is not evidence.

The [upstream API documentation](https://github.com/ibireme/yyjson/blob/8b4a38dc994a110abaec8a400615567bd996105f/doc/API.md)
defines raw-number parsing, length-aware strings and custom allocators. The
fixed policy and bounds above are package requirements, not claims that the
upstream parser enables them by default.

The current reader is `json_codec.c`. Its caller supplies one bounded pool,
keeps it alive until `wop_json_clear`, and clears a successful document before
reusing that output object. Failed reads retain no live document. Generic syntax
validation admits no SDK operation. `ipc.c` applies closed outer request keys
and exact generation/deadline/timeout widths in the executable; field-specific
parameter validation and closed per-operation keys remain mandatory at the
service adapter.
