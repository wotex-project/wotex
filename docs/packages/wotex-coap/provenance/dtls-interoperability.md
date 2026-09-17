# Independent DTLS verification

`test/interop/dtls_pki_test.exs` exercises the native WCO-S05 profile against
libcoap 4.3.5 with its OpenSSL backend. OTP implements the client's DTLS record
layer; libcoap/OpenSSL implements the peer. This is independent-stack DTLS
evidence. It does not accept OSCORE or the complete software stress matrix.

The WCO-V12 assertions cover both exact DTLS 1.2 cipher suites, complete
Block1/Block2 operations, DNS/IP SAN identities, PKCS#1/PKCS#8 client keys,
PSK identity/key failures and mismatched security modes. PKI failures include
expired, wrong-SAN, CN-only, wildcard, wrong-KU, wrong-EKU and unknown-critical
certificates; unrelated trust roots; revoked certificates; expired CRLs; and
invalid CRL signatures. The unchanged public DER fixtures are identified by
`test/fixtures/dtls_pki/manifest.json`.

A test-owned UDP proxy observes actual client datagrams. Every exchange remains
DTLS-framed; rejected authentication never falls back to a cleartext CoAP request.
For each security mode, a captured authenticated record is delivered once,
replayed without another plaintext delivery, and followed by a fresh authenticated
response. Corrupt ciphertext produces an error within the native interaction
budget, not a representation. Native Observe tests establish, change and cancel
the original relationship through two explicit authenticated sessions.

Real `Wotex.Runtime.ConsumedThing` calls exercise all three admitted media types
over PSK and PKI with both immediate and configured credential custody. Reads,
writes and Actions preserve request identity, the selected resolved Form and
unknown extensions. JSON null, false, zero, empty arrays and nested values remain
distinct; larger text and binary values traverse blockwise transfer. Authentication
failures return typed Runtime errors without plaintext traffic. Property and
Event subscriptions deliver initial and updated values, then release their
authenticated sockets on explicit stop or receiver death. An unrelated stop
Form cannot redirect cancellation.

The fixture owns its selected executable, listener pair, proxy sockets and
temporary PEM/identity files. Readiness is bounded to five seconds and captured
peer output to 1 MiB. Normal shutdown requires the peer's zero exit status;
termination escalates after one second and waits at most one additional second.
Explicit test closure checks that client/proxy UDP ports and the peer's UDP/TCP
listener pair can be rebound. Failed tests retain supervisor-owned cleanup.
All generated files reside in unique system-temporary directories. No peer
starts when this library is loaded or when the ordinary suite excludes interop.

## Reproduce the peer

Use the unmodified archive for commit
`7cf7465b784baded4de183290c547d582becfd28`, SHA-256
`d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd`.
The production OSCORE patch set is not applied to this independent DTLS peer.
The selected build uses CMake, a C compiler and an explicit OpenSSL prefix.
Configure from the unpacked source directory: upstream CMake probes Git in its
invocation directory, which must not identify an unrelated source checkout.

The following shell example creates only external build artifacts. Set
`openssl_prefix` to the installed OpenSSL prefix before running it.

```sh
peer_workspace="$(mktemp -d)"
peer_revision=7cf7465b784baded4de183290c547d582becfd28
curl -fL --max-time 60 -o "$peer_workspace/libcoap.tar.gz" \
  "https://codeload.github.com/obgm/libcoap/tar.gz/$peer_revision"
printf '%s  %s\n' \
  d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd \
  "$peer_workspace/libcoap.tar.gz" | shasum -a 256 -c -
tar -xzf "$peer_workspace/libcoap.tar.gz" -C "$peer_workspace"
(
  cd "$peer_workspace/libcoap-$peer_revision"
  env -u LDFLAGS -u CPPFLAGS cmake -S . -B "$peer_workspace/build" \
    -DENABLE_DTLS=ON -DDTLS_BACKEND=openssl \
    -DOPENSSL_ROOT_DIR="$openssl_prefix" -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=ON -DENABLE_TESTS=OFF \
    -DENABLE_OSCORE=ON -DWARNING_TO_ERROR=ON -DCMAKE_BUILD_TYPE=Debug
)
cmake --build "$peer_workspace/build" --parallel 4
WOTEX_PATH_DEPS=1 \
WOTEX_COAP_LIBCOAP_SERVER="$peer_workspace/build/coap-server" \
  mix test test/interop/dtls_pki_test.exs --include interop
```

The fixture requires an absolute executable path and a libcoap 4.3.5/OpenSSL
version response, then prints the executable's SHA-256. Missing executables,
readiness failures and absent responses fail the test; they are not skips.
A version string alone does not establish source provenance. Retain the verified
source archive, build options, compiler/OpenSSL versions, printed executable
digest and test output outside the repository for a particular execution.
The server uses the documented `-L 1` block mode, dynamic resource support and
PUT echo, with an explicit matching PSK identity entry or supplied PKI material.

## Scope and remaining evidence

Run the focused native/security tests on Elixir 1.18.4/OTP 27.3.4.15 and
Elixir 1.20.2/OTP 29.0.4 with separate build/dependency directories. The
complete authoritative library gate remains `WOTEX_PATH_DEPS=1 mix check --no-retry`;
this explicit peer suite does not replace it. Existing OTP-peer tests additionally
cover security input bounds, weak RSA admission, owner interruption and Runtime
credential/stream ownership.

The source basis is RFC 6347 (January 2012), RFC 5280 (May 2008), RFC 7252
(June 2014), RFC 7641 (September 2015) and RFC 7959 (August 2016), with the
fixed cipher, offline revocation and exact identity policies in WCO-S05.
[The pinned libcoap server manual](https://libcoap.net/doc/reference/4.3.5/man_coap-server.html)
defines the peer options. Complete chain-depth fault expansion, independent
secure Runtime overload/deadline faults, Linux sanitizer/stress evidence, OSCORE and WCO.13's
build/run task acceptance remain separate obligations. Historical receipts retain
their original source, command and narrower claims.
