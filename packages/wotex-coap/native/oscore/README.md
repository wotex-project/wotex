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
exact C07 Message results. Larger legal results emit correlated begin/chunk/end
frames followed by a Message body reference, all under the original request
deadline. One protected Observe registration retains its initial report until
cumulative credit opens, emits larger reports through credited begin/chunk/end
frames, admits fresh subsequent reports, and cancels with the original token.
At Max-Age expiry it either re-registers the same route and token with a new
Message ID under the original finite command timeout or sends best-effort
cancellation and emits `observation_stale`. A zero Max-Age renews no more often
than once per second, and the initial report is completely written first.

`native_worker_test.exs` runs the same executable through custody on macOS. It
asserts exact ready/open/body/request/close envelopes, printable-ID escaping,
live store locking, consumed-identity rejection and malformed-input teardown.
`Dockerfile.json` compiles the cohort with ASan/UBSan on Linux and feeds a
coalesced lifecycle trace through the internal worker entry. The
[lifecycle receipt](../../docs/provenance/native-worker-lifecycle-v1.json) binds
that preceding source cohort and its limits. The
[exchange receipt](../../docs/provenance/native-worker-exchange-v1.json) binds a
same-stack protected GET and Block1 POST through the public custody entry on
macOS and Linux. The subsequent
[stream receipt](../../docs/provenance/native-worker-stream-v1.json) binds a
32,769-byte Block2 result and the immediately following Block1 POST. The Linux
lane builds the patched static SDK plus the production adapter with ASan/UBSan
and leak detection. The subsequent
[Observe receipt](../../docs/provenance/native-worker-observe-v1.json) binds
protected registration, zero-credit retention, two inline reports, cumulative
acknowledgment and token-matched cancellation. The following streamed-report
[receipt](../../docs/provenance/native-worker-report-stream-v1.json) binds the
five credited frames of a 32,769-byte notification and
cancellation with all five credits outstanding. The subsequent
[renewal receipt](../../docs/provenance/native-worker-renewal-v1.json) binds
same-token/new-MID renewal, the zero-Max-Age minimum interval and disabled-renewal
stale cleanup. The following
[observation-fault receipt](../../docs/provenance/native-worker-observation-faults-v1.json)
binds negative, missing-Observe, changed-Content-Format and timeout renewal
outcomes plus one latest Property report and terminal Event overlap at exhausted
credit. These receipts do not accept notification freshness injection, live
replay behavior, independent OSCORE interoperability or the final Mix-built
executable.

The [freshness receipt](../../docs/provenance/native-worker-freshness-v1.json)
binds the worker's native equal/older/half-range/128-second admission primitive,
including stale metadata ordering, and a protected same-stack FFFFFF-to-zero
Observe wrap. The [stale-notification receipt](../../docs/provenance/native-worker-stale-notification-v1.json)
binds the same admission through the Mix-built helper: a captured authenticated
notification relayed again after a newer one yields no value.

The [renewal/cancel receipt](../../docs/provenance/native-worker-renewal-cancel-v1.json)
binds a protected cancellation admitted while renewal remains in flight. It
executes the public-API original-route/token fallback, one distinct cancellation
Message ID and exact deadline-driven local cleanup when no usable confirmation
arrives. Its `timeout` came from libcoap's OSCORE send hold rather than the peer:
under the send-hold patch the peer's response confirms that cancellation within
the command deadline. The
[intervening-response receipt](../../docs/provenance/native-worker-intervening-response-v1.json)
binds a notification that reaches the worker between a renewal or cancellation
and its response: it is neither a report nor cancellation success, and the
pending exchange still completes.

The [owner-cleanup receipt](../../docs/provenance/native-worker-owner-cleanup-v1.json)
binds abrupt public-custody owner EOF after a protected observation is
established. Worker exit cleanup sends one original-route/token cancellation,
the peer removes its observer and custody reaps the helper within C03. The
[pending owner-loss receipt](../../docs/provenance/native-worker-pending-owner-loss-v1.json)
binds the same bound when owner EOF arrives while registration, renewal or
cancellation still awaits the peer: exit cleanup sends exactly one cancellation
for a registration or renewal and none after a pending cancellation.

The [output-saturation receipt](../../docs/provenance/native-worker-output-saturation-v1.json)
binds an actual owner pipe filled to `EAGAIN`, fourteen protected 16 KiB
notifications across two credit intervals, continued network progress and the
same bounded owner-loss cleanup while report output is backpressured. The
software run separately samples a suspended BEAM owner's Port mailbox at no more
than eight report frames and delivers a terminal beside the full window.

The [network-wait receipt](../../docs/provenance/native-worker-network-wait-v1.json)
binds readiness-driven exchange progress. The worker waits on libcoap's epoll
descriptor and next timer, or passes its owner pipes to
`coap_io_process_with_fds` on builds without epoll, and then collects exact owner
descriptor events with a zero-timeout poll. Thirty-two sequential protected GET
exchanges complete in less than one second.

The [stale-traffic receipt](../../docs/provenance/native-worker-stale-traffic-v1.json)
binds random 8-byte initial tokens, discarded responses without a request
association and a 20 ms exit window in which the best-effort cancellation's
confirmable peer response is acknowledged before custody signals the worker. The
[malformed-datagram receipt](../../docs/provenance/native-worker-malformed-datagram-v1.json)
binds ignoring libcoap's discarded-datagram event instead of closing the exchange.
The [notification-verification receipt](../../docs/provenance/native-worker-notification-verification-v1.json)
binds discarding a notification that fails OSCORE processing without cancelling
the observation. While a renewal or cancellation is pending, the same failure is
also discarded, because the pending request refreshed libcoap's token association
and a notification still in flight cannot verify against it.

The sequence patch makes `coap_send` fail before encryption when the public
`coap_oscore_save_seq_num_t` callback rejects a reservation. It advances the
cached reservation only after callback success. Repeated failures therefore
cannot bypass persistence through a previously advanced cache. The empty-byte
patch preserves the CBOR encoding of an empty byte string without calling
`memcpy` on its null source.

The OSCORE Observe patch preserves the authenticated response Partial IV before
libcoap substitutes the request Partial IV for AAD construction. Decrypted
Observe values therefore retain the response's low 24 bits for RFC 7641 serial
freshness instead of repeating the registration request sequence.

The response-admission patch prevents plaintext nonempty responses from reaching
an OSCORE application's response callback. It reports a finite protection error,
including for an unauthenticated error response; its diagnostic text is not
trusted. Empty ACK/RST preserve their transport-only meaning. The
[protection receipt](../../docs/provenance/native-protection-v1.json) covers
15 real UDP fault responses and ordinary UDP, empty-RST and protected positive
controls. The protected
peer uses the same pinned SDK and is labelled same-stack. The fixture reservation
callback is not the production durable store.

The send-hold patch removes libcoap's OSCORE client hold from `coap_send`. A
client recipient context never leaves its initial replay state, so libcoap
re-armed the hold on every send; while any request lacked a response, the next
PDU construction ran `coap_client_delay_first` and blocked the worker for up to
five seconds. The worker serializes exchanges and bounds each with its own
deadline, so a cancellation behind an unanswered registration or renewal is sent
at once.

The unverified-response patch keeps a request's OSCORE association when a
correlated message fails verification. libcoap deleted a non-Observe association
on any decryption error, so a notification protected for the registration
removed the association of a pending cancellation and the genuine confirmation
then found none. RFC 8613 section 8.4 stops processing an unverified message;
it cannot change security state.

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
streaming, live replay and the full OSCORE workflow remain separate implementation
obligations.

The patches retain libcoap's source licensing; see
[LICENSE.libcoap](LICENSE.libcoap) and the package [NOTICE](../../NOTICE).
Generated SDK sources, build products and keys do not belong in the package.
