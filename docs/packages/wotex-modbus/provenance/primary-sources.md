# Modbus primary sources

Research date: 2026-09-08. Audience: library maintainers. Scope: classic TCP,
binary values and the WoT mapping profile; no certification claim.

- Modbus Organization, [Application Protocol V1.1b3, 26 April 2012](https://www.modbus.org/file/secure/modbusprotocolspecification.pdf), §§4–7.
  PDU ≤253 bytes; TCP ADU ≤260 bytes. Read limits: 2000 bits or 125 registers;
  multiple-write limits: 1968 bits or 123 registers. Register bytes are big-endian,
  coil bits least-significant first. Function-specific echoes and exception
  responses must be validated. Address and quantity must fit the 16-bit space.
- Modbus Organization, [TCP/IP Implementation Guide V1.0b, 24 October 2006](https://www.modbus.org/file/secure/messagingimplementationguide.pdf), §§3.1.3, 4.4.
  MBAP length counts Unit Identifier and PDU. Match Transaction Identifier,
  Unit Identifier and function. TCP framing must handle partial reads. Full PDF
  retrieval failed; official indexed sections corroborated these fields.
- W3C, [TD 1.1 Recommendation, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/).
  Core Form values and operation defaults are delegated to Wotex.
- W3C, [Modbus binding draft](https://w3c.github.io/wot-binding-templates/bindings/protocols/modbus/index.html),
  source revision `ea0ec98f864feca914e175026c441c3c36e8b1a9` (2026-08-26).
  Work in progress. Uses `modbus+tcp`, `/{unitID}/{address}`, `quantity`, and
  `modv:` terms. Inconsistent function capitalization and infinite timeout
  default are resolved by the explicit Wotex profile, not a conformance claim.
- libmodbus, [v3.1.12](https://github.com/stephane/libmodbus/tree/9af6c16074df566551bca0a7c37443e48f216289),
  released 2026-02-13. Independent TCP server chosen for interoperability.

Protocol framing, bounds and draft mapping use the cited revisions. Physical
hardware and Modbus Security certification remain separate evidence.

## Software scope and source authority

The .10 scope deliberately completes the eight-function TCP client rather than
adding unreviewed serial/security transports. The official
[Modbus Security v36, 2021-07-30](https://www.modbus.org/file/secure/modbussecurityprotocol.pdf)
was inspected for that boundary: it includes certificate/role behavior beyond a
generic TLS tunnel. [Serial Line Guide V1.02, 2006-12-20](https://www.modbus.org/file/secure/modbusoverserial.pdf)
defines a separate serial framing/timing profile. Neither is a claimed implemented
cell here. Library admission/cleanup limits in .00/.10 are local design policy.
The independent software fixture remains
[libmodbus v3.1.12 source](https://github.com/stephane/libmodbus/tree/9af6c16074df566551bca0a7c37443e48f216289).

## Standalone source authority

WMB.11 preserves the eight named function helpers and float helpers already in
the native API. Its exact wire examples were checked against the official
Application Protocol V1.1b3 sections listed above. Typed engineering-value
composition, strict map admission and the fixture oracle are library policy.
The corpus defines exact cases; execution evidence binds cases to source and
toolchain identities. Wotex core/Runtime remain owners of TD values/interaction mechanics.
