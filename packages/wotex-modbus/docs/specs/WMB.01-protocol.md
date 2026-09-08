# WMB.01 Modbus values and TCP exchanges

## Ownership and revision

Implements the explicitly listed function subset of Modbus Application Protocol
V1.1b3 (2012-04-26) and TCP/IP Guide V1.0b (2006-10-24). See primary-source
provenance. Application register maps, polling, serial hardware, authorization,
Modbus Security and canonical Property state are consumer responsibilities.

## Public values

`Address.new/3` accepts a zero-based offset 0..65535, positive quantity, and
unit 1..247 or 255. A range may not cross 65536. The narrower unicast profile
rejects broadcast/reserved units. `Command.new/4` supports read coils, discrete
inputs, holding/input registers and single/multiple coil/register writes.
Reads admit 2000 bits or 125 registers; writes admit 1968 bits or 123 registers.
Only booleans or 0/1 are coil inputs. Invalid values return `Error`, never crash.

Conversion supports signed/unsigned 16/32/64-bit integers and IEEE754 finite
32/64-bit floats. Explicit byte and word order are application conventions;
wire register encoding remains big-endian. Input lengths must exactly match
the selected type; non-finite float encodings are rejected.

## Codec

TCP decoder is incremental, returns a complete frame and unconsumed tail,
`:more` for incomplete input, or a structured failure. Length must be 2..254
and Protocol Identifier zero before body allocation. Response validation
matches transaction, unit, function, byte count and complete write echo.
Exception responses are exactly two bytes, preserve the numeric remote code,
and never masquerade as success. Coil padding must be zero.

## Lifecycle and errors

A consumer explicitly starts a connection. One process owns the socket and
serializes exchanges. Every call carries an absolute monotonic deadline so
queue time counts and expired calls cannot issue writes. No implicit retries.
Timeout, malformed response or correlation failure closes the session; a late
response cannot satisfy a later request. Disconnect is idempotent. Owner death
closes the socket. Load alone starts nothing. Connection health means local
socket ownership only; compatibility health performs the documented read.
Connection options are allowlisted and unique. Unknown or duplicate keys,
including misspelled or conflicting security selectors, fail before TCP startup.

`Error` contains library-owned code/field/details, retryable=false, and an effect
of `:none` or `:unknown`. Any failed write after transmission conservatively
reports unknown effect. Payloads, credentials and host identifiers do not enter
telemetry. Events are `[:wotex, :modbus, :request, :stop]` with duration in native
units and result/function metadata.

## Evidence

`codec_test.exs`: official-shape golden bytes, quantity edges, exception and echo
failures, all frame splits, coil padding, arbitrary malformed input properties.
`value_test.exs`: range and register roundtrips with byte/word orders.
`connection_test.exs`: independent loopback socket peer, split response,
correlation failure, deadlines, disconnect and owner termination.
`test/interop`: independent libmodbus server and exact read/write assertions.
