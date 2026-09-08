# BACnet primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract above
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and evidence still requiring hardware or SDK execution.

- [BACstack 0.0.1 Client](https://bacstack.hexdocs.pm/BACnet.Stack.Client.html).
- [Pinned BACstack package](https://repo.hex.pm/tarballs/bacstack-0.0.1.tar).
- [BACstack ClientHelper](https://bacstack.hexdocs.pm/BACnet.Stack.ClientHelper.html).
- [ASHRAE standard availability](https://bacnet.org/buy/).
- [ASHRAE COV interpretation 135-2012-18, 2015-11-04](https://bacnet.org/wp-content/uploads/sites/4/2022/08/IC135-2012-18.pdf).
- [W3C BACnet binding draft](https://w3c.github.io/wot-binding-templates/bindings/protocols/bacnet/index.html).

Research searched standards/revision availability, wire/address rules, transport
ownership, security and interoperability gaps, then reviewed upstream APIs.
Stop reason: consequential design claims have primary evidence or explicit
access limits. No physical or secure-stack execution was performed by research.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

Independent execution reference:
[BACnet C stack commit 3603048350b8ba543ec76cf6aa8a232b3f4d442d](https://github.com/bacnet-stack/bacnet-stack/tree/3603048350b8ba543ec76cf6aa8a232b3f4d442d).
The exact source builds the server fixture used for read/write/negative-response
proof. Upstream has ongoing parser security fixes; this source snapshot is a
local interoperability fixture, not a recommendation to deploy a public server.
