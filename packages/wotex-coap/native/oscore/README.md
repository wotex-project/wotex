# Native OSCORE sources

The native target uses libcoap 4.3.5, identified by the archive, ordered patch
hashes and resulting source hashes in [source.json](source.json). Builds must
verify all three stages; an unmodified upstream build is not this target.
[WCO.13](../../docs/specs/WCO.13-native-build-and-software-evidence.md) owns the
Port, durable storage and build contract. `main.c`, `worker.c` and `exchange.c`
implement the same-binary custody entry and the first production libcoap
exchange slice. The Mix build task remains incomplete.

The public executable accepts only `--custody ABS_DIRECTORY`; custody executes
that same absolute file with only the internal `--worker` argument. The worker
emits the pinned ready identity, applies the native frame/command decoder,
decodes and erases OSCORE credentials, consumes the durable context with an
initial exclusive boundary of 32, owns one verified upload body, and releases
the store after its correlated close result is written. A 512 KiB nonblocking
output queue retains per-frame deadlines. Invalid framing or state terminates
the generation. A `WCO_WITH_LIBCOAP` build verifies the exact package version,
creates one fixed-profile OSCORE context/session, binds libcoap's public
sequence-save callback to the durable store, and dispatches one unary request at
a time. libcoap owns tokens, retransmission and whole-body Block1/Block2
assembly. Complete protected responses up to the 32 KiB inline boundary become
exact C07 Message results. Larger legal results return `native_unavailable`
until stdout body streaming is implemented. Observe, credit and cancel retain
the same finite pre-network error.

`native_worker_test.exs` runs the same executable through custody on macOS. It
asserts exact ready/open/body/request/close envelopes, printable-ID escaping,
live store locking, consumed-identity rejection and malformed-input teardown.
`Dockerfile.json` compiles the cohort with ASan/UBSan on Linux and feeds a
coalesced lifecycle trace through the internal worker entry. The
[lifecycle receipt](../../docs/provenance/native-worker-lifecycle-v1.json) binds
that preceding source cohort and its limits. The
[exchange receipt](../../docs/provenance/native-worker-exchange-v1.json) binds a
same-stack protected GET and Block1 POST through the public custody
entry on macOS and Linux. The Linux lane builds the patched static SDK plus the
production adapter with ASan/UBSan and leak detection. It does not accept
streamed output bodies, Observe, report credit, replay behavior, independent
OSCORE interoperability or the final Mix-built executable.

The sequence patch makes `coap_send` fail before encryption when the public
`coap_oscore_save_seq_num_t` callback rejects a reservation. It advances the
cached reservation only after callback success. Repeated failures therefore
cannot bypass persistence through a previously advanced cache. The empty-byte
patch preserves the CBOR encoding of an empty byte string without calling
`memcpy` on its null source.

The response-admission patch prevents plaintext nonempty responses from reaching
an OSCORE application's response callback. It reports a finite protection error,
including for an unauthenticated error response; its diagnostic text is not
trusted. Empty ACK/RST preserve their transport-only meaning. The
[protection receipt](../../docs/provenance/native-protection-v1.json) covers
15 real UDP fault responses and ordinary UDP, empty-RST and protected positive
controls. The protected
peer uses the same pinned SDK and is labelled same-stack. The fixture reservation
callback is not the production durable store.

The real native regression in `test/native/oscore_sequence_test.c` creates an
OSCORE client through public libcoap APIs and a local UDP receiver. It asserts
three failed reservations each produce `COAP_INVALID_MID` and zero received
datagrams, followed by a separate context whose three permitted sends contain
OSCORE options and stay within its reserved sequence boundary. This is a
sequence-callback primitive, not a durable filesystem or interoperability test.
The test's key material is a public RFC 8613 fixture.

`test/native/Dockerfile` builds and runs the actual pinned SDK and regression
with Linux ASan/UBSan, including leak detection. Its input context contains the
verified archive as `source.tar.gz`, every ordered source patch and the native
fixtures named by its COPY entries. The base image
is pinned; package versions are recorded after installation, not claimed to be
fixed by the image digest. [The receipt](../../docs/provenance/native-sequence-v1.json)
records exact test/source/artifact digests and the executed macOS/Linux lanes.
It does not accept the remaining OSCORE helper, store, framing or Mix tasks.

`identity.c` derives the fixed suite's sender/recipient keys and Common IV
through OpenSSL HKDF solely to identify storage namespaces. It hashes each
direction's key and nonce prefix, in addition to the full input identity, so
changing an unrelated peer ID or equivalent salt encoding cannot authorize
reuse of consumed key material. The C.1–C.3 exact vectors and input boundaries
execute in `oscore_identity_test.c`.

`store.c` implements the explicit private-directory registry and exclusive
lease described by WCO-N04. `wco_store_open` consumes an identity and reserves
an exclusive sequence boundary before returning success. `wco_store_reserve`
acknowledges only durable allowances; persistence failure permanently disables
that owner. `wco_store_close` releases its two descriptors without deleting
consumed records. The native header defines the finite status API and limits.
No bridge operation can use this store until the caller has opened it explicitly.

`oscore_store_test.c` exercises real filesystem writes, locks, child-process
crashes, SIGKILL, malformed state, capacity and exhaustion. Test-only fault hooks
interrupt the actual atomic-write stages; they are absent from the production
object. `oscore_store_send_test.c` binds this store to the patched libcoap
callback and asserts zero wire datagrams after every storage-failure stage.
[The store receipt](../../docs/provenance/native-store-v1.json) identifies these
assertions and their source bytes. The production exchange adapter now binds
this store to libcoap's sequence callback before protected transmission. Report
credit, live replay, streamed responses and the full OSCORE workflow remain
separate implementation obligations.

The patches retain libcoap's source licensing; see
[LICENSE.libcoap](LICENSE.libcoap) and the package [NOTICE](../../NOTICE).
Generated SDK sources, build products and keys do not belong in the package.
