---
spec:
  id: WMB.09
  title: "Optional inert register-decimal codec"
  status: accepted
  version: 1.0.0
  owner: wotex-modbus
  updated: 2026-10-08
---

# WMB.09 Optional inert register-decimal codec

This package extension projects explicitly supplied register bytes to WRT.06
inert values. Packed BCD is an application data convention, not a Modbus or
W3C-standard representation. No exchange, pairing, Property truth or Action
authority follows decoding. Ordinary Form mapping and scalar conversion remain
independent. An executable delivery profile needs its own consumer usefulness
and native qualification; this pure projection establishes neither.

## R01 — Contract and API

`Wotex.Modbus.RegisterCodec` implements the public
`c:Wotex.Runtime.Codec.Decoder.decode/3` callback. Its arguments are explicit
bytes, metadata and non-secret configuration. Returns are `{:ok, node}` or
`{:error, :invalid_input | :unsupported_format | :unsupported_value |
:output_limit}`. Every malformed input is refused without raising or retaining
foreign data. Loading and decoding perform no I/O and read no ambient state.

`contract/0` returns the exact `{id, version, sha256}` string-keyed reference:
id `wotex.modbus.register-decimal`, version `1.0.0`, SHA-256 over the exact
canonical JSON bytes in `priv/fixtures/register_codec/contract.json`.
`configuration_schema/0` returns `{id, sha256}` with id
`wotex.modbus.register-decimal.config`, hashing the exact canonical JSON bytes
in `priv/fixtures/register_codec/configuration.schema.json`.
References are embedded at compilation; these functions do not read files.

`validate_configuration/2` takes configuration and the exact schema reference
and returns `:ok` or `{:error, :invalid_configuration}`. It is the pure explicit
validator supplied to WRT.04 Plan.new/4. The consumer installs the decoder
module under its exact contract reference and chooses the trusted executor.
No module is selected from descriptor strings. Altered schema references fail
before any decoder work.

## R02 — Input and output grammar

Configuration is a closed string-keyed object with exactly `registers`
(integer 1..4), `byte_order` and `word_order` (`big` or `little`), `scale`
(integer -32768..32767) and `signed` (boolean). Metadata is exactly
`{"format":"packed-bcd-v1"}`. A different string format is
`unsupported_format`; wrong shape or type is `invalid_input`.

Input length is exactly twice registers. Bytes initially follow Modbus's
network register order. Apply word reversal first when word_order is little,
then reverse the two bytes within each word when byte_order is little.
Unsigned input uses every nibble as a decimal digit 0..9. Signed input uses
its last nibble as C (positive) or D (negative), and all preceding nibbles as
digits. Other digits/signs are invalid_input. Leading input zeros are allowed.
Negative zero is unsupported_value, preserving WRT.06's signed-zero refusal.

Return a WRT.06 decimal coefficient/exponent node. Coefficient is the decoded
integer and exponent starts at scale. Repeatedly remove nonzero coefficient
trailing zeros and increment exponent. Canonical zero has exponent 0.
Normalized exponent outside -32768..32767 is unsupported_value. Four registers
bound the coefficient to 16 unsigned or 15 signed digits, below signed 64-bit
limits. No binary floating conversion, inferred unit or rounding occurs.

## R03 — Evidence and data-only control

Tests cover every byte/word order, signed/unsigned/zero, invalid digits/signs,
wrong lengths and metadata/configuration fields, normalization overflow,
identity substitution and repeated/cross-generation deterministic output.
They traverse public Runtime Codec with explicitly consumer-supervised Beam
execution as well as the pure decoder, without granting transport credentials.
Archive acceptance verifies both embedded references against shipped exact
documents and exercises the decoder from the isolated candidate consumer.

Changing an ordinary scalar's existing modv:type/byte/word ordering is a
data-only control and does not need this codec or implementation admission.
The existing scalar grammar cannot express BCD validation and decimal
normalization; this extension supplies that bounded projection. A library
extension or data grammar may still meet a consumer's full replacement need.
No external host is justified by fixture presence or this algorithm alone.

Independent process implementations, installed closure/memory enforcement,
consumer cost criteria and physical-device qualification are separate open
requirements in the portable delivery programme and WRT.06. No standards
conformance, performance, adoption or independent-language claim is made here.
