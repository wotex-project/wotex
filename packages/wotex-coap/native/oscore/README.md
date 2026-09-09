# Native OSCORE sources

The native target uses libcoap 4.3.5, identified by the archive, ordered patch
hashes and resulting source hashes in [source.json](source.json). Builds must
verify all three stages; an unmodified upstream build is not this target.
[WCO.13](../../docs/specs/WCO.13-native-build-and-software-evidence.md) owns the
Port, durable storage and build contract. The production executable and Mix
build task are not implemented by these patches.

The sequence patch makes `coap_send` fail before encryption when the public
`coap_oscore_save_seq_num_t` callback rejects a reservation. It advances the
cached reservation only after callback success. Repeated failures therefore
cannot bypass persistence through a previously advanced cache. The empty-byte
patch preserves the CBOR encoding of an empty byte string without calling
`memcpy` on its null source.

The real native regression in `test/native/oscore_sequence_test.c` creates an
OSCORE client through public libcoap APIs and a local UDP receiver. It asserts
three failed reservations each produce `COAP_INVALID_MID` and zero received
datagrams, followed by a separate context whose three permitted sends contain
OSCORE options and stay within its reserved sequence boundary. This is a
sequence-callback primitive, not a durable filesystem or interoperability test.
The test's key material is a public RFC 8613 fixture.

`test/native/Dockerfile` builds and runs the actual pinned SDK and regression
with Linux ASan/UBSan, including leak detection. Its input context contains the
verified archive as `source.tar.gz`, both patches and the C test. The base image
is pinned; package versions are recorded after installation, not claimed to be
fixed by the image digest. [The receipt](../../docs/provenance/native-sequence-v1.json)
records exact test/source/artifact digests and the executed macOS/Linux lanes.
It does not accept the remaining OSCORE helper, store, framing or Mix tasks.

The patches retain libcoap's source licensing; see
[LICENSE.libcoap](LICENSE.libcoap) and the package [NOTICE](../../NOTICE).
Generated SDK sources, build products and keys do not belong in the package.
