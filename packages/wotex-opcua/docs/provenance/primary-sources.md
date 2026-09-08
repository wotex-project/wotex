# OPCUA primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract above
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and evidence still requiring hardware or SDK execution.

- [Part 6 metadata, revision 1.05.07](https://reference.opcfoundation.org/specs/OPC-10000-6).
- [Part 6 binary and transport clauses](https://reference.opcfoundation.org/specs/OPC-10000-6/full).
- [Part 4 RequestHeader](https://reference.opcfoundation.org/specs/OPC-10000-4/7.32).
- [Part 4 certificate validation](https://reference.opcfoundation.org/specs/OPC-10000-4/6.1.3).
- [Part 2 Security None](https://reference.opcfoundation.org/specs/OPC-10000-2/4.8).
- [OPC 10101 WoT URI format](https://reference.opcfoundation.org/specs/OPC-10101/6.2).
- [OPC 10101 security](https://reference.opcfoundation.org/specs/OPC-10101/6.3).

Research searched standards/revision availability, wire/address rules, transport
ownership, security and interoperability gaps, then reviewed upstream APIs.
Stop reason: consequential design claims have primary evidence or explicit
access limits. No physical or secure-stack execution was performed by research.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

Implementation-specific follow-up: [asyncua 2.0.1 package](https://pypi.org/project/asyncua/2.0.1/),
[Client API](https://opcua-asyncio.readthedocs.io/en/latest/api/asyncua.client.html),
[validator implementation](https://github.com/FreeOpcUa/opcua-asyncio/blob/v2.0.1/asyncua/crypto/validator.py).
The installed 2.0.1 source was inspected: hostname checks are not active in its
validator. The bridge therefore adds exact SAN/endpoint checks, a server pin,
chain verification and a signed/current issuer CRL check. The trust profile is
restricted to direct CA issuance. A real same-stack secure peer proof is recorded
separately in executable-evidence.md; it is not independent interoperability.
Python dependency audit on 2026-09-08 reported no known vulnerabilities for the
fully pinned requirements. That result is time-bound and must be rerun.
