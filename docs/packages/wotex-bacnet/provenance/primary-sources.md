# BACnet primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and required independent software evidence.

- [BACstack 0.0.1 Client](https://bacstack.hexdocs.pm/BACnet.Stack.Client.html).
- [Pinned BACstack package](https://repo.hex.pm/tarballs/bacstack-0.0.1.tar).
- [BACstack ClientHelper](https://bacstack.hexdocs.pm/BACnet.Stack.ClientHelper.html).
- [ASHRAE standard availability](https://bacnet.org/buy/).
- [ASHRAE COV interpretation 135-2012-18, 2015-11-04](https://bacnet.org/wp-content/uploads/sites/4/2022/08/IC135-2012-18.pdf).
- [W3C BACnet binding draft](https://w3c.github.io/wot-binding-templates/bindings/protocols/bacnet/index.html).

The reviewed evidence covers wire/address rules, transport ownership, security
boundaries and upstream APIs. It is source analysis, not protocol execution.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

Independent execution reference:
[BACnet C stack commit 3603048350b8ba543ec76cf6aa8a232b3f4d442d](https://github.com/bacnet-stack/bacnet-stack/tree/3603048350b8ba543ec76cf6aa8a232b3f4d442d).
The exact source builds the server fixture used for read/write/negative-response
proof. Upstream has ongoing parser security fixes; this source snapshot is a
local interoperability fixture, not a recommendation to deploy a public server.

## Software-contract review, 2026-09-08

The pinned 0.0.1 package source was inspected at `Stack.Client`, `ClientHelper`,
`SegmentsStore`, `Segmentator`, `Services.SubscribeCov`, `SubscribeCovProperty`
and confirmed/unconfirmed notification modules. Local Client.subscribe registers
an APDU listener; it does not send SubscribeCOV. Client.reply uses the received
reference to correlate confirmed-service acknowledgment. Cancel requires both
optional confirmation/lifetime fields absent; lifetime zero is indefinite.
Construct cancel APDUs explicitly instead of inheriting helper defaults.

[BACstack 0.0.1 SegmentsStore API](https://hexdocs.pm/bacstack/0.0.1/BACnet.Stack.SegmentsStore.html)
documents the max_segments option. The target sets 32 explicitly rather than
using the unlimited-style default. The .10 aggregate/admission/lifetime ceilings
are library policy. [Pinned C-stack COV service source](https://github.com/bacnet-stack/bacnet-stack/tree/3603048350b8ba543ec76cf6aa8a232b3f4d442d/src/bacnet)
is the independent fixture reference. Full ANSI/ASHRAE paid clauses remain an
access limitation; source-level and software-peer evidence must not be described
as full-standard or BTL certification.

## Standalone-client review, 2026-09-09

The pinned package's `ClientHelper.who_is/3` accepts `low_limit`, `high_limit`,
`apdu_destination`, `max` and `no_subscribe`. Omitting destination asks the Client
for a broadcast address. The WBA.11 policy requires explicit configuration and
an independently bounded operation owner; the helper's default destination and
Task timing are not the public lifecycle contract. I-Am is an unconfirmed
observation without a Who-Is transaction identifier. Sequential `read_properties`
composition does not become a ReadPropertyMultiple service claim.

Source encoding checks through BACstack 0.0.1 produced the exact Who-Is APDUs
`1008` and `10080901190a`, and SubscribeCOV cancellation parameter bytes
`09071c00400000`, as recorded in the specified WBA-F05/F06/F07 cases. These
cross-checks validate the chosen upstream byte examples; they do not execute
independent Wotex discovery/COV peer workflows or accept those work packages.

## Runtime and fixture boundaries

The production SDK is BEAM BACstack. C-stack builds and their compiler/container
requirements belong to the independent software fixture; no Python or native
executable supplies production BACnet transport.

The pinned [IPv4Transport source](https://hex.pm/packages/bacstack/0.0.1/files/lib/bacnet/stack/transport/ipv4_transport.ex)
uses active-ten UDP receive and rearms from its own handler before downstream
consumption. Its PID callback forwards decoded messages without consumer credit.
The [TransportBehaviour](https://hexdocs.pm/bacstack/0.0.1/BACnet.Stack.TransportBehaviour.html)
is the public seam for the package's required bounded BEAM transport. S03a's
credit count, starvation timeout and datagram bound are library policy, not an
ASHRAE requirement or an existing BACstack callback.

## Independent COV fixture

The pinned C stack's
[server registration](https://github.com/bacnet-stack/bacnet-stack/blob/3603048350b8ba543ec76cf6aa8a232b3f4d442d/apps/server/main.c)
and [COV handler](https://github.com/bacnet-stack/bacnet-stack/blob/3603048350b8ba543ec76cf6aa8a232b3f4d442d/src/bacnet/basic/service/h_cov.c)
implement SubscribeCOV. Its public cov.h supplies a SubscribeCOVProperty codec,
but the server has no corresponding handler. The instrumented fixture links the
unmodified SDK object-COV handler. Its resource observations decode the actual
Active_COV_Subscriptions representation and read the public transaction table.
The Property fixture uses that SDK's public SubscribeCOVProperty and COV
notification codecs with a separate bounded table. The pinned
[Analog Output implementation](https://github.com/bacnet-stack/bacnet-stack/blob/3603048350b8ba543ec76cf6aa8a232b3f4d442d/src/bacnet/basic/object/ao.c)
encodes its thresholded prior value for object COV. Property subscriptions read
the actual Present_Value and maintain their own last-report value, so a requested
increment below the object's default has independent semantics.
The fixture's finite control interface and loss controls are first-party test
code; they are not production SDK extensions or a certification claim. Their
exact scope is in [the fixture contract](../../../../packages/wotex-bacnet/test/interop/cstack/README.md).

## Hex source identity

The [Hex package format at specification revision cd9e0004](https://github.com/hexpm/specifications/blob/cd9e0004c226d69be5897426f453ba1c967f5e70/package_tarball.md)
defines the format-3 VERSION, metadata.config, contents.tar.gz and CHECKSUM
members. CHECKSUM covers the concatenated version, metadata and compressed
contents. The package's outer SHA-256 identifies the complete archive.
The fixture verifier checks both pinned values against the Mix lock and checks
every installed package file against the verified archive. Archive/file bounds
and rejection of additional installed source are fixture policy, not Hex
package-format requirements. The exact checks and executable evidence are
described in [source verification](../../../../packages/wotex-bacnet/test/support/software/README.md).
