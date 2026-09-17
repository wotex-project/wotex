---
spec:
  id: WMB.02
  title: "Form profile and compatibility"
  status: accepted
  version: 1.1.0
  owner: wotex-modbus
  updated: 2026-09-09
---

# WMB.02 Form profile and compatibility

This library implements a bounded subset of the W3C Modbus binding draft,
source revision `ea0ec98f864feca914e175026c441c3c36e8b1a9` (2026-08-26).
This is a Wotex profile, not W3C conformance.

Use `modbus+tcp://IP[:port]/{unit}/{address}?quantity=N`. Port defaults to 502;
quantity to one. Human Form addresses default to one-based, while
`modv:zeroBasedAddressing=true` selects wire offsets directly. Host resolution
is consumer-owned: the native TCP transport accepts numeric IPv4/IPv6 only.
Userinfo, fragments, duplicate/unknown query terms and ambiguous paths fail.

A Form needs `modv:entity` (Coil, DiscreteInput, HoldingRegister, InputRegister)
or lowercase `modv:function` using the eight function names in `Mapping`.
Entity takes precedence, as in the draft. Read-only entities cannot write.
An Action requires an explicit mutation function; any entity-selected function
must match that explicit function. Explicit contentType is rejected before I/O
because this profile exposes native values without a serialization codec.
Only readproperty, writeproperty and invokeaction are implemented. Wotex core
applies contextual operation defaults; declared operations still constrain use.
Polling and observation scheduling are not implemented.

Optional `modv:type` accepts xsd:short, unsignedShort, int, unsignedInt, long,
unsignedLong, float and double. Byte and word ordering flags default to true.
Absent type returns raw register/coil lists. Other Form extensions are retained
verbatim without claims about their meaning. This profile does not implement
`modv:timeout` or `modv:pollingTime`; the explicit transport timeout is authoritative.
A scalar conversion requires an exact matching width and otherwise fails.

`Wotex.Modbus` is the compatibility adapter. Callback names and arities match
the neutral protocol interface. Reads return `{:ok, values}`; writes `:ok`;
optional subscriptions `:not_supported`; failures contain `Wotex.Modbus.Error`.
The PDU capability is 253 bytes, write replay is disabled, input
limits are strict, numeric hosts are required, and errors are structured.
Consumer adoption requires explicit compatibility assertions for these boundaries.

`Wotex.Modbus.Transport` implements the Runtime request port, scopes one session
to one interaction, uses finite deadlines covering connection and exchange,
and returns identity-bound Runtime Results. Credentials are not accepted by
the classic TCP profile. Unsupported security never downgrades. Persistent
polling consumers can use explicit `Connection` child specifications instead.
Runtime configuration admits only `timeout` and `security: :none`; malformed,
unknown or duplicate keys return a structured error before network access.
