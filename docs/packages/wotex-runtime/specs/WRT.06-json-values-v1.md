# WRT.06 — Exact JSON value decoder

Version: 0.1.0. Updated: 2026-10-15. Status: accepted owned successor.
Owner: WRT.06 C01/C02/C03/C05. Implementation: planned. Evidence: missing.

## Result and boundary

`Wotex.Runtime.Codec.JSON` decodes RFC 8259 JSON bytes into the existing C02
inert value algebra. It implements `Wotex.Runtime.Codec.Decoder.decode/3` and
provides `decode/1` for the same pure operation with empty metadata/configuration.
It never converts a number through a native float. This utility owns one generic
byte format; it owns no protocol, selector, semantic unit, device, clock, source
sequence, authorization, transport, file, registration or worker.

[WRT.06](WRT.06-bounded-codec.md) owns the unchanged C02/C03 representation,
canonical Value encoding, registered execution and isolation boundaries. The
utility produces an inert value only; using it through an executor still needs
that caller's exact registered contract and admission. No process is started by
loading or calling the module. Existing wire/descriptor parsers remain unchanged.

## Closed API and bounds

**J01.** `decode/1` accepts only one binary containing a complete JSON value,
with optional JSON whitespace (space/tab/CR/LF) before and after it. Input is
1–65,536 bytes. UTF-8, JSON escapes/surrogates and syntax follow RFC 8259; reject
BOM, invalid bytes, extra values, trailing commas, comments, NaN and Infinity.
Reject repeated object names after escape decoding, including equivalent escaped
names. `decode/3` requires metadata and configuration to be exactly empty ordinary
maps; any nonempty map, struct or other value returns unsupported_format.

Input JSON containers become C02 list/object nodes. Object entries sort by
original decoded UTF-8 key bytes without Unicode normalization. Keys are 1–128
UTF-8 bytes, as C02 requires; empty or unrepresentable keys refuse unsupported_value.
Strings become text, booleans remain Boolean and null remains null. String-looking
numbers remain text. No bytes, missing-value sentinel or protocol default is inferred.

**J02.** An integer JSON token becomes sint if within signed 64-bit range,
otherwise uint only for positive values at most 18446744073709551615. Reject
larger/smaller integers as unsupported_value, even if another numeric notation
could represent their mathematical value. Canonical decimal strings are emitted;
integer -0 becomes sint "0". No arbitrary-precision output type is added.

A token containing a fraction or exponent becomes decimal, even when its value
is integral. Concatenate integer/fraction digits, apply sign, remove leading zeroes
and trailing coefficient zeroes, and adjust the base-ten exponent exactly.
Zero always becomes coefficient "0", exponent 0, including negative zero and
exponent forms. Nonzero coefficient must fit signed 64-bit and have no trailing
zero; final exponent is an integer in -32768..32767. No rounding, clamping,
underflow, Double conversion or exponent-sized power allocation is permitted.
A valid numeric token longer than 128 bytes returns output_limit before integer
conversion. Normalization may bring an otherwise large textual exponent into
range; the final normalized values control representability.

Examples: `1` -> sint "1"; `9223372036854775808` -> uint of that value;
`1.2300e2` -> decimal coefficient "123", exponent 0;
`-0.0e999999` -> decimal coefficient "0", exponent 0;
`9007199254740993.1` -> decimal coefficient "90071992547409931", exponent -1.
JSON object order and whitespace do not change the corresponding typed value.
Fraction/exponent versus integer spelling deliberately retains the stated type
choice; this is not an RFC 8785 number-normalization operation.

**J03.** Enforce the unchanged C02 bounds: root typed-node depth 1, maximum
depth 8, 1024 typed nodes, 256 members per collection, 4096 decoded UTF-8 bytes
per text and 128 per key, and at most 65,536 bytes after `Value.encode/1`.
Count containers and values, not object keys or the C02 wrapper members. Reject
before retaining an excess member/node or entering excess container depth.
A primitive child also increases typed depth. Check the complete input byte
ceiling before parsing and numeric token length before numeric conversion.
Decoded strings are bounded before retaining their C02 representation. Parsing
may transiently hold a single scalar within the fixed input ceiling; these are
engineering allocation bounds, not a measured native-memory qualification.

## Failure and compatibility

**J04.** Success is exactly `{:ok, value}` and `Value.validate/1` must accept
that value. Refusal is exactly `{:error, code}` where code is invalid_input,
unsupported_format, unsupported_value or output_limit. Syntax/UTF-8/duplicates/
nonbinary/empty input give invalid_input; unsupported numeric/key representation
gives unsupported_value; byte/depth/node/member/text/token/output ceilings give
output_limit. Fixed metadata/configuration mismatch takes precedence in decode/3.
Malformed syntax may be refused before another limit when both are violated;
no partial value is returned. Exceptions, parser offsets, object names, source
bytes and native error text never enter a refusal, inspection or telemetry.

The operation is deterministic and stateless: repeated/cross-process calls use
no cache, clock, randomness or current environment. No retry, scheduling, file or
lifecycle effect is introduced. C02 validation/encoding and old codec/wire formats
retain their exact accepted grammar and bytes. OTP's public json:decode/3
callbacks, available since OTP 27, supply syntax/UTF-8 decoding; exact numeric
callbacks receive original tokens and never materialize binary floating point.

## Entry, independent vectors and acceptance

Before code, freeze literal JSON inputs, expected typed values/canonical Value
bytes and refusal codes in `test/support/codec_json_vectors.json`. Its standalone
Python generator/checker uses Python's JSON parser with exact Decimal tokens,
duplicate-name rejection and independent C02 construction. It imports no BEAM,
Runtime implementation or encoder. Production encode is checked against those
expected canonical bytes, not used to allocate them.

| Case | Requirements | Stimulus and falsifier | Level |
| --- | --- | --- | --- |
| J-T1 | J01/J02/J04 | Every JSON kind, Unicode/escapes/order, S64/U64 extrema and beyond-double precision, fraction/exponent normalization and negative zero. Rounded, coerced or wrongly typed output fails. | Independent software vectors |
| J-T2 | J01–J04 | Duplicate/escaped names, invalid syntax/UTF-8, wrong native API arguments, numeric overflow and token length, empty/long key, exact/one-over byte/depth/nodes/members/text/output bounds. Partial value, exception or payload-bearing error fails. | Public native API |
| J-T3 | J03/J04 | Repeated/concurrent calls, complete Value validation/encoding parity and ordinary codec facade/BEAM use with explicit registered fixture contract. Effect, mutable state, changed identity or old-wire regression fails. | Software/existing executor |

Executed checks and remaining native-memory/host/independent-process obligations
must be reported separately; none of these cases establishes a network publisher
or physical evidence.

## Primary sources

- [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259): JSON syntax, UTF-8 and interoperable object names.
- [OTP json:decode/3](https://www.erlang.org/doc/apps/stdlib/json.html#decode/3): public scalar/container callbacks and leftover bytes, available since OTP 27.
- WRT.06 C02/C03 and the existing Value implementation at ba8ea373244ce57987f47a731b8eca3ccae9b45f own representability and canonical output.
