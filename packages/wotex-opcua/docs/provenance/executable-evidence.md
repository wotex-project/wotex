# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
That historical baseline covered the stated toolchain only. The package
requires fresh source-specific matrix and archive checks before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. The native build test is required by this
gate: it downloads the pinned archives, executes the static build and CTest, and
checks receipt reuse/tampering in an owned temporary workspace. The gate requires
CMake 3.20+, a C11 compiler, make, Perl, Python 3, archive utilities and curl 8.4.0+.
`mix test` excludes this lane; selecting `native_build` without its explicit
`WOTEX_NATIVE_BUILD_WORKSPACE` fails. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Explicit public native Session client slice, 2026-09-16

The explicitly selected `Wotex.OPCUA.Open62541` client now implements the
existing client port with caller-owned persistent and one-shot secure Sessions.
Persistent connect snapshots bounded credential files, verifies the executable
identities, activates the native Session and retains its temporary host until
explicit disconnect or owner loss. One-shot connect validates shape without
file or process I/O; each request snapshots credentials, opens a temporary
Session, performs one service operation and closes it. The client validates
concrete NodeIds and typed Variant inputs before dispatch, with no automatic
mutation retry. It currently returns the validated native DataValue, Write
status and Call result maps through the public facade. Browse, subscriptions,
complete one-shot compatibility projection, full lifecycle/cancellation and
the security policy/token matrix remain open. The older `Asyncua` adapter and
its production Python bridge still exist, so the repository is not yet
Python-free; selecting `Open62541` invokes no Python runtime code.

Six default public-client tests pass. A C response peer injects deterministic
open/read/write/call/close frames to test owner, credit and cleanup wiring;
it does not establish OPC UA interoperability. Nine optional tests pass against
the independent Basic256Sha256 anonymous asyncua 2.0.1 peer. The public facade
there reads, writes/reads back/restores a Double and calls a typed Method in a
persistent Session; a one-shot read independently opens and closes another
secure Session. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes
on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 280 passed (10 doctests,
4 properties, 266 tests), ten optional tests excluded and 95.0% coverage.
Its native build, documentation, dependency audits and package/archive checks
pass. This is partial P02/S02/X04 evidence, not package acceptance.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/open62541.ex` | `fa9e0578462c801687a19c008b9eab1225454bc4fad4d1703d6903672d7c0382` |
| `lib/wotex/opcua.ex` | `6a322c21d190a2e236e08553f4305fa7910a1ed6426e120fdef77179fab7c5b4` |
| `lib/wotex/opcua/port_call.ex` | `fd5aac1a7814c22d11641dc6905bb190c54ebe0e2d5040eee4bb2030a3ea2312` |
| `test/wotex/opcua/open62541_test.exs` | `7ae6e55d997325055912a1b59f0413b2ca30d052a161199434203454ac89e2b8` |
| `test/interop/native_secure_test.exs` | `6729cff2cc49ee60e4a8123bee0ee12a09202744ad6ca205e36c1a75dc96e04d` |
| `test/native/host_probe.c` | `b6c799b743dc365e3462aac8c309164882b943519c78c3ad231c3737fc872ef9` |

## Native credential configuration projection, 2026-09-16

`Native.Config.new/1` now rejects unknown or duplicate option keys, malformed
native executable identities, insecure policy/mode shapes, invalid token forms,
non-absolute credential paths and out-of-range timeouts before file I/O.
`open_parameters/2` snapshots only named regular files under one monotonic
deadline, caps each at 64 KiB, rejects an excessive aggregate frame, and emits
the closed DER/bytes-envelope map for the existing C `open` request. The config
inspect form omits credential paths and binary passwords. Unit tests cover
anonymous, binary username and certificate token projection, the file and
aggregate limits, and invalid options. An eighth optional independent-peer
test opens and closes a real Basic256Sha256 anonymous Session using this
projection. The helper is preparatory: no public `Open62541` client or one-shot
projection exists, the public adapter remains Python-backed, and P02/P03 and
the full policy/token matrix remain open.

The focused configuration suite passes five default tests. Eight optional
secure-peer tests pass. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry`
gate passes on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 274 passed
(10 doctests, 4 properties, 260 tests), nine optional tests excluded and 95.1%
coverage. Documentation, audits, native build and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/config.ex` | `83b7b168170e9afdc60b24ee46d9610dfcf86c2b4c9d9eb847b7363aacc63181` |
| `test/wotex/opcua/native/config_test.exs` | `ad7e3c3685fc00981ef1369949fdea6b2506cb996acd9486e4aa50cd6cc049bd` |
| `test/interop/native_secure_test.exs` | `aacb17ab1b8e8b85ba84adc48373a1d9a0198d4cf5c782728729f8fdb9806611` |

## Asynchronous native Method Call slice, 2026-09-16

The production C process now admits one Method Call after secure activation.
It translates concrete object and method NodeIds through the server NamespaceArray
and SDK-local namespace map, validates 0..64 typed input Variants, copies their
storage into SDK-owned memory and retains it until asynchronous completion or
client cleanup. The callback copies one bounded method result. The process and
BEAM owner validate the numeric method status, ordered input argument statuses
and typed outputs before spending and replenishing output credit. A Bad method
status or post-submission failure has unknown effect and is not retried. The
owner also preserves unknown effect after an unacknowledged Call timeout or
Port loss. NodeId-bearing inputs and outputs remain unsupported pending complete
namespace translation. This does not accept full P02/S02/X04, concurrent
operations, cancellation, subscriptions or the public native client; the
default public adapter remains Python-backed.

The focused Frame/Host suite passes 30 default tests, including the Call owner
timeout and 64-element result boundaries. Seven optional tests pass against the
independent Basic256Sha256 anonymous asyncua 2.0.1 peer: a real two-Double
Method Call returns ordered typed output, while a missing method preserves a
numeric Bad status and unknown effect. The independent peer is test-only Python.
The RelWithDebInfo native CTest suite passes 181/181. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 269 passed (10 doctests, 4 properties, 255 tests),
eight optional tests excluded and 95.2% coverage. Its fresh native build,
documentation, dependency audits and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `8c0295cdddc484b910dae91e91f0d582d62c4e7667dd7f7fd81c55c2a3aeb8b1` |
| `priv/native/session_open.c` | `e68603d04c7a2f4f23a7650f46daeb8b0a2830e94601f5a9fb544671d114c597` |
| `priv/native/session_open.h` | `3b103bef14f96a9ceb322508f4ab30d97846e6ff18276bd7e82c17e18b569866` |
| `lib/wotex/opcua/native/frame.ex` | `b5475fcd19c0cc06b031f813061e41f5d33a75c4db94d9ff68bd0d75ee810547` |
| `lib/wotex/opcua/native/host.ex` | `12c8c4236517aca7596e52b3339b21d458bec6c497a51389d0ebee9892defdc8` |
| `test/interop/native_secure_test.exs` | `f6b93a70ee2bc399ab051432dcd077b39bfecff36d30520c4da2607f79c772d2` |
| `test/interop/secure_peer.py` | `6b2eae7899b593afb98502dd478239579e7555634bdbe73ce9a82a70b5ee4174` |
| `test/wotex/opcua/native/frame_test.exs` | `a5ebadacdec692f80be570c463993f4d3ff367932d0051a70bd1c292b80fd62b` |
| `test/wotex/opcua/native/host_test.exs` | `16a36bbab3cd5818a9ebcd2cd21c9beeee5636c94ce95e81bae4e26a8fb8690b` |
| native CTest log | `dec6b9587d122962d837ced64444f9ad73a831773b2f5f2287a164e3cde7f5a2` |

## Asynchronous native Value Write slice, 2026-09-16

The production C process now admits one typed Value Write after secure
activation. It validates the closed node/index-range/Variant map, resolves the
input namespace URI to the SDK-local index, copies the Variant into SDK-owned
memory, and retains that copy until asynchronous completion or client cleanup.
One individual numeric Write status is returned. A Bad result or post-submission
timeout/connection failure reports unknown effect, and the BEAM owner also
classifies an unacknowledged Write after Port loss or local timeout as unknown.
There is no automatic replay or retry. NodeId-bearing Variant values remain
unsupported until namespace translation is complete. This partial slice does
not accept complete P02/S02/X04, concurrent operations, cancellation or the
public native client; the default public adapter remains Python-backed.

The focused Frame/Host suite passes 29 default tests, including an unacknowledged
Write owner-timeout case. Six optional tests pass against the independent
Basic256Sha256 anonymous asyncua 2.0.1 peer: a typed Double Write is read back
and restored, and a rejected Write retains its numeric Bad status and unknown
effect. The RelWithDebInfo native CTest suite passes 181/181 cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 268 passed (10 doctests, 4 properties,
254 tests), seven optional interoperability tests excluded and 95.2% coverage.
Its fresh native build, CTest, documentation, dependency audits and
package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `46fd01fb27c230dcd137641f4b721319e6c65ded38630077591a2a127300935d` |
| `priv/native/session_open.c` | `b9cad696a853719b5b3af737e2f40a66654c6518b9f18903c3eab05f41eb7ff2` |
| `priv/native/session_open.h` | `7fbf7e6e5d5aec4be78f26bd8610d8c26101d746e6e0b251d065d701616c623d` |
| `lib/wotex/opcua/native/frame.ex` | `49b0e24a10ea05026bb9b5703c44d8fe1a92b244e42cdecb3bcc9b673a1eb383` |
| `lib/wotex/opcua/native/host.ex` | `5131a51e2dae3300fea89c19f196b03cb90aa85cb2a0966faaa3ac779388e8ae` |
| `test/interop/native_secure_test.exs` | `6b3f03e5419912f7aee9a18265bb5e600b30f0392b8d260b59d95f4f91497fb4` |
| native CTest log | `a8e5b0e0935b302629ecda5a9e92c5897ba5d2e652dee83201ec9315fe097582` |

## Asynchronous native Value Read slice, 2026-09-16

The production C process now admits one concrete Value Read after secure
activation, with a null index range, one asynchronous SDK request and one
correlated IPC result. It resolves the public server namespace index through
its URI to the SDK-local index and checks the reverse mapping before issuing
the request. The existing native value codec emits the full bounded DataValue;
the BEAM frame decoder validates its typed shape before credit replenishment.
Bad attribute status returns finite `remote_error` with the numeric StatusCode.
NodeId-bearing result Variants remain explicitly unsupported until the inverse
namespace mapping exists. This does not accept P02/S02/X04 as a whole or bind
new X-F cases: cancellation, concurrent operations, output buffering, the other
services and the public native client remain open. The public default adapter
still requires Python.

The focused Frame/Host suite passes 27 default tests. Four optional tests pass
against one independent Basic256Sha256 anonymous asyncua 2.0.1 peer, including
the actual executable and BEAM owner reading a Double and a Bad read retaining
its StatusCode. The RelWithDebInfo native CTest suite passes 181/181 cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 266 passed (10 doctests, 4 properties,
252 tests), five optional interoperability tests excluded and 95.2% coverage.
Its fresh native build, CTest, documentation, dependency audits and
package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `41b1713c8f63a14f95d2d9398c4a5f7e260e81eec2fb6335d41bce80c44eb279` |
| `priv/native/session_open.c` | `539e02450f036c6e60317c6390deabeafd1e9b45a7ba90cdac79e773d87524fc` |
| `priv/native/session_open.h` | `21040e48879919fa0cc66a72f7710908b31fa8bcb4fbef7ed2e0f7c9896912e6` |
| `lib/wotex/opcua/native/frame.ex` | `a35e3f80b55f9944f70fcf3d7e29c7554892c42735ceab507835bfe2aa80073d` |
| `test/interop/native_secure_test.exs` | `4446e122a981a070d83dbdca72fe795ad86fb25b54c4c6c5dfd37b2deb8cab76` |
| native CTest log | `5288b8a82cac815e4283b3ca61d6c554f50564bee13f73d03486f6b8bdee4fef` |

## Production secure open/close slice, 2026-09-16

The production `wotex_opcua_native` now runs the strict open-parameter and
credential gates, starts an asynchronous pinned SignAndEncrypt SDK Session,
reads the server NamespaceArray independently, rejects malformed/duplicate or
oversized namespace entries and an invalid/excessive revised timeout, then emits
one generation/ID-correlated success under the initial output credit. The
process retains the Session until explicit close or EOF. Close attempts an
asynchronous CloseSession with subscription deletion and bounded cooperative
teardown before its success response. The internal BEAM `Native.Host` decodes
only the closed open/close result shapes, maps the owner deadline and replenishes
validated response credit. `Native.Frame` rejects mismatched generation, ID,
timeout and namespace metadata.

The independent asyncua 2.0.1 peer passes three optional interop checks: the
C-only secure probe, the production executable's direct framed open/close, and
the BEAM owner through the separate custody guardian. The focused Frame/Host
unit suite passes 24 tests, including a default owner success/credit fixture;
the three optional peer checks passed separately. The RelWithDebInfo native
suite passes 181/181 CTest cases. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 263 passed (10 doctests, 4 properties, 249 tests),
four optional interoperability tests excluded and 95.2% coverage. Its fresh
native build, CTest, documentation, dependency audits and package/archive
checks pass. This is one Basic256Sha256 anonymous peer lane;
it does not accept P02/P03, bind X-F17..F23, expose a public native client,
implement Read/Write/Call/Browse/subscriptions or remove the existing Python
runtime adapter.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `1b624910dd28bc07f359f21dff1a376fe6b8d07fb030bddc07a30839156b3f3b` |
| `priv/native/session_open.c` | `6cc1de2505fb77d6f0c2cb3ac7d2420a0a48b0fe8dc7af7d68e6f7d9b5702f67` |
| `priv/native/session_open.h` | `e121325623b89da1e569432d280e8913736c6e240e2d3b2ddeb91042b937f314` |
| `lib/wotex/opcua/native/frame.ex` | `500c7cc2dd5b2bf642843ffd58090c863bf712bbfd8cdcbca42a012b2ae7538e` |
| `lib/wotex/opcua/native/host.ex` | `e0d27f1441d66bb39a31cb9029101177b0a3c5f8ee483327f624012a9e252a4d` |
| native CTest log | `3f2627eb8e22f488279950b6de4f00403eb054de67552854548fb23b3f06f99d` |
| full gate log | `7992337aaaae807ae5f931cb08d56a90e6306904b8e51a197e845166315bb7b2` |

## Secure SDK configuration prerequisite, 2026-09-16

At that prerequisite stage, `open62541-secure-discovery-v2` extended the reviewed, exact-hash SDK patch:
when a caller supplies the pinned leaf and SignAndEncrypt policy, GetEndpoints
runs over that first secure channel. Endpoint URL and certificate substitution
and ambiguous matching user-token policies fail before CreateSession. The
existing revised Session timeout preservation remains. The source manifest
binds all pristine and patched file digests and the patch script. At this stage,
the production executable still rejected a valid `open` as `unsupported_protocol`.

`session_config.c` now configures the requested policy and explicit anonymous,
username or certificate token, installs the whole-DER pin/CRL/SAN/URI verifier
as the SDK callback, preserves a binary username password and forbids key
prompts or automatic reconnect. The C credential test passes 60 generated
cases and 145 assertions without network I/O. The uninstalled C Session probe
then connects to an independent asyncua 2.0.1 loopback peer using
Basic256Sha256 SignAndEncrypt, reads the actual server NamespaceArray (three
entries) and checks the server's positive, bounded 60000 ms revision. The
both optional ExUnit interop tests pass against that live peer. The RelWithDebInfo
native suite passes 181/181 CTest cases. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 261 passed (10 doctests, 4 properties, 247 tests),
two optional interoperability tests excluded and 95.8% coverage. Its fresh
native build, static SDK patch, CTest, documentation, dependency audits and
package/archive checks pass. These checks establish a prerequisite,
not the production owner, all policy/token combinations, services or P02/P03
acceptance. The normal runtime adapter still requires Python.

| Subject | SHA-256 |
| --- | --- |
| source manifest | `6cc2163a1ce9dca4c237a0b7a8da8af5f52c1869ae45b90464ab13e09e3523d1` |
| `priv/native/patch-sdk.cmake` | `df1acabefca781711a34b546e4a3ded85af95a46110cf9b0978685fd340fad2a` |
| `priv/native/session_config.c` | `4dcc0045f599a3b56e10de777a6fa5cecbaa624277bb0e35bbc508851257dce3` |
| `priv/native/session_config.h` | `35969525091fce3fd4ec0f19ba683ce804e92ea8286467392b1141e1a7205ee3` |
| `priv/native/session_probe.c` | `fc0fb3b41b718efe5340c313e1cf24b8e8b258e7acacc24cc7a5d0f0920449a5` |
| native CTest log | `54709fa7a0c742b1a0b4d15c543ced1ed9fa4e18f432110af77d4353241201c7` |

## SDK Session revision preservation, 2026-09-16

The pinned open62541 build now applies `open62541-session-revision-v1` before
SDK configuration. Its CMake script checks all three pristine file hashes and
all three transformed file hashes before writing anything. The source manifest
records those identities and the script digest. All modified files and the
patch log are receipt artifacts; tampering rejects build reuse. The required
build test independently extracts pristine upstream source, corrupts each of the
three inputs in turn, and checks that a rejected patch changes none of them.
It then checks the exact successful outputs and rejects reapplying the patch.

`native_sdk_session_revision` uses an actual SDK server bound only to loopback
and drives three asynchronous SDK client Sessions. It compares server-revised
`3210.5` ms against a 60000 ms request, equal 60000 ms limits, and a 1000 ms request
below the server maximum. It asserts the scalar and copied Double, rejects the
attribute before activation and after disconnect, and checks that the copied
value survives Session cleanup. This separate test binary uses Security None;
it proves SDK metadata preservation, not secure native owner acceptance. The
production executable still cannot open a Session. The adapter must still reject
invalid or excessive revisions before delivering an open result.

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 261 checks (10 doctests, 4 properties, 247 tests),
one interoperability test excluded and 95.8% coverage. It includes a fresh
patched static SDK build, the patch corruption/reapplication/reuse assertions,
docs, dependency audits, package inspection and out-of-tree archive compilation.
The RelWithDebInfo native suite passes 181 CTest cases. A Debug
`WOTEX_SANITIZERS=ON` build passes all 170 cases selected by
`ctest --output-on-failure -R 'native_(security|sdk|ipc|json|value|contract)'`,
using `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. The first-party driver/parser sources are
instrumented; the pinned static SDK/OpenSSL inputs are not. Linux security,
full native Session admission, secure peers and the Python-runtime replacement
remain required. No additional X-F case or P02/P03 acceptance is inferred.

| Subject | SHA-256 |
| --- | --- |
| source manifest | `4f9525afe5c6856e1421ad8524825163d27428bbc7e02b44bfca5674d53a0964` |
| `priv/native/patch-sdk.cmake` | `658028a4d97114cf98144bea0881bd0bbed4a174c29096e2f96b43d239e257cc` |
| `priv/native/sdk_revision_check.c` | `ce6658f299ab424d3fb2b0770d28771e819ac27c55c476a13384faf30d59e994` |
| `lib/wotex/opcua/native/recipe.ex` | `91c6d5821766abb21b84fc350d93bb3aa127a241cad6fe4947c49bf929d75c37` |
| `lib/wotex/opcua/native/build.ex` | `e83d653a2d053e5d6ed4062551946ca563960b1b1aea4cd1b7206988fe51ce37` |
| `test/wotex/opcua/native/build_test.exs` | `90b3073ce0928fe665a6958c8a61de5461c8516ae0f5b52e0bbd172a99187b2d` |
| native CTest log | `9a6351becd985aaa60bfbec793c4ae55affdcf2ae52c97ed5b5f2b0ce204cbb5` |
| native ASan/UBSan log | `279e0a6c141a72aa40905a63a756ce55a34e671a2ebef337ee2316de1ce5b11d` |

## Native credential preflight, 2026-09-16

The pre-network S03/X03 slice adds `priv/native/security.c` to the production
executable and hash-bound native build. `native_security_preflight` generates
ephemeral credentials in C, passes them through the strict JSON/open-parameter
boundary, and asserts 60 cases plus 36 peer-pin/time checks (96 assertions).
Inputs cover all three admitted policy names and token forms, DER/PKCS#8 and
container faults, key mismatch and weak keys, strong and weak signatures,
RSA-PSS certificate/CRL signatures, direct issuer versus intermediate trust,
DNS/IP/URI mismatch, wildcard/CN rejection, key usage/EKU, critical/duplicate
extensions, revocation and exact validity/update boundaries. Rejected input
must release every credential acquisition; repeated clear is safe. Unknown
noncritical certificate extensions remain admissible. This is preflight
evidence, not network policy or authentication interoperability.

On macOS arm64, the RelWithDebInfo native build passes all 180 CTest cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes with Elixir
1.20.2 / OTP 29.0.4: 260 checks (10 doctests, 4 properties, 246 tests), one
interoperability test excluded and 95.8% coverage. Its fresh pinned native
build, docs, dependency audits, package inspection and out-of-tree archive
compilation all pass.
The Debug `WOTEX_SANITIZERS=ON` build passes all 169 tests selected by
`ctest --output-on-failure -R 'native_(security|ipc|json|value|contract)'`, with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. First-party sources/parser are instrumented;
the pinned static SDK/OpenSSL inputs are not. Clang static analysis of
`security.c` reports no diagnostics. These runs do not establish Linux security
or leak-detection acceptance.

The required Mix build test invokes the real executable with shape-valid but
invalid DER and asserts one `certificate_invalid` terminal, phase `opening`,
matching generation and no credential content. The native request's original
monotonic deadline is checked again after credential work. The C peer verifier
checks an exact whole-DER pin and current trust but is not yet installed as the
SDK callback. Valid preflight still ends with `unsupported_protocol`; P02/P03,
X-F30..F47 and replacement of the Python runtime remain unaccepted.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/security.c` | `1e962e1580c5ee87991855980da471ad91a0ccfcc7019c9bb4f47086b96960f3` |
| `priv/native/security.h` | `34f636e010b145ba352424e3c1632c8226a3ed41ac5873a6c208228568644157` |
| `priv/native/security_check.c` | `8606ebf29e52aced99f467964e97d94b133983c7e0fb7de7f3c31ceb728a41e1` |
| `priv/native/main.c` | `2e217de4101f938642fb45e41e9aa5b9d5f2932d8a527a15bfe5114f2d804367` |
| `priv/native/CMakeLists.txt` | `6614c2559a74e2d2e713ccba4932ac42a2a0308fed7eea9a29bfc01437693588` |
| `test/wotex/opcua/native/build_test.exs` | `ecdbd8ca7ca78b64c518e1a520f2815368e3ccdedb69c331e6ffd0e16969479f` |
| native CTest log | `1750b3454a9f95a42d88381e87edc3a4b7c5b51b55b74d038e69db5e99a63081` |
| native ASan/UBSan log | `ed28a066c82f5d691f5eb9fe352e941e592ee1190597f54adf51f02173e10960` |

## WOP-P00 source, build and custody cohort

WOP-P00 passed on 2026-09-14 for the source/build/bootstrap and portable
process-custody boundary. `WOTEX_PATH_DEPS=1 mix check --no-retry` used Elixir
1.20.2 / OTP 29.0.4 on macOS 26.6.2 arm64. Coverage was the only ExUnit pass:
254 tests passed, one interoperability tag was excluded, and coverage was 96.3%.
The selected native build downloaded and verified the pinned source archives,
built static OpenSSL/open62541 and both first-party executables, then passed all
161 CTest cases. The native CTest output SHA-256 was
`e79c866df4d8debb3cdba9e8b9126b46f3ccba07cf2e987680b091c52da7442e`.

The build receipt bound these identities:

| Subject | SHA-256 |
| --- | --- |
| native source manifest | `909bb2cca1eeb20e755af093cc24b896ba94b578b81ee25d4924cfc406ae73b9` |
| open62541 1.5.7 source archive | `a4018b052c93fedb55f00558a85869b86f3bb2293184d322e33f2666c497eaeb` |
| OpenSSL 3.5.8 source archive | `59f86483992995df5a213df38d93f31eeafe3b34599309b3e088ba67ca0aad9c` |
| macOS arm64 `wotex_opcua_native` | `8c52d02d2ab66d95c36e9d5266ca8b5d15b24107837178f5656a2ebaeaeb3781` |
| macOS arm64 `wotex_opcua_custody` | `c3cd34e996542c79fbc9031e8067bb41bbe7415a5132e981c7a72db1296e5197` |
| custody fixture | `bd69b4c0bff4a43ae7318c95702d23e925ca93190c62bc88f52b508b4b306144` |
| runtime guardian source | `d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2` |
| independent custody driver | `ef8c45b3bea8727a8a9e6be0fe4985d8a798ff0d5bee1b870a6346f5ede498e5` |

WOP-G10 additionally passed in Linux arm64 and x86_64 containers resolved from
`debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171`.
Each architecture executed WOP-G01 through WOP-G09 once with strict
AddressSanitizer/UndefinedBehaviorSanitizer timing and once with LeakSanitizer:
18 executions per architecture, zero failures. The independent Linux driver
asserted exact byte/count/status projections, SDK reap within 500 ms, guardian
exit within the applicable allowance, and absence of leaked direct children.
`bin/check_native_custody.exs` makes those Linux sanitizer lanes part of the
default gate; macOS runs the portable corpus through the native build and CTest.

This evidence accepts P00 only. The native helper still exposes dependency and
bootstrap behavior, not a secure Session or application service. P01 and later
packets, complete native service framing, independent peers, the full platform
matrix and an archive-only native consumer remain required separately.

## WOP-P01 typed value and namespace cohort

The P01 gate uses Elixir 1.20.2 / OTP 29.0.4 on macOS arm64 with the locked
development dependencies. `WOTEX_PATH_DEPS=1 mix check --no-retry` passes 254
checks (10 doctests, 4 properties and 240 tests), with one interoperability test
excluded and 96.3% coverage. The required fresh native build passes 178 CTest
cases, including every WOP-X-F01 through WOP-X-F16 projection and WOP-NF17
namespace fault case. Build receipts bind the native contract fixture separately
from the first-party source files and upstream archives.

A separate Debug build enables `WOTEX_SANITIZERS=ON` and runs
`ctest --output-on-failure -R 'native_(value|contract|json)'` with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. All 167 selected tests pass on macOS arm64.
The same 167 cases also pass on Linux x86_64 with leak detection enabled,
using the pinned Debian image recorded for P00, GCC 12.2.0 and CMake 3.25.1.
Both builds instrument the first-party native sources and parser with
AddressSanitizer/UndefinedBehaviorSanitizer; their static SDK and OpenSSL inputs
retain the pinned versions recorded for P00 and are not sanitizer-instrumented.

An isolated Elixir 1.18.4 / OTP 27.3.4.15 run passes the default suite:
10 doctests, 4 properties and 241 tests, zero failures and two exclusions
(`interop` and `native_build`). That run does not repeat the SDK build.

| P01 input | SHA-256 |
| --- | --- |
| native contract corpus | `b1505300b4bcb5d0fd596c67a6e027bcbef123b386c8f379f0bd0ecf5e995ec1` |
| typed value corpus | `b38f6fc3b8ea23fd55a2c899146bb643376b6e4ace9af3b71d1221615b0db1ec` |
| native contract runner | `748535edab646afbe7847f5e4af8d42c824fa05c72850ebea0033918465ac0f9` |
| value codec implementation | `ef7a4b16e6485fec0f903e2f55aedadf3a982fa0c662ec0bb07cb5a781ba7593` |
| value codec header | `1aeef02790f45be1071ec6a0063cb40d70b8e4e49880b60b876052187e658b16` |
| direct SDK fault runner | `433783382e1b74dc6560440e5af2f14359af07c754819dd41f128b875c362c4f` |

P01 accepts pure typed values, identity/reference preservation, SDK value
projection and exact namespace translation. The namespace arrays are explicit
inputs to a pure primitive. Their acquisition and lifetime, native Sessions,
services, subscriptions and independent peers remain required by later packets.

## Initial WOP-P02 input boundary (package remains open)

On 2026-09-16, the actual `wotex_opcua_native` process used `ipc.c` and the
strict production JSON reader to assemble and validate an outer request line.
`native_ipc_admission` exercises every split of its valid line, two coalesced
lines, the exact frame ceiling, NUL rejection, closed keys, duplicate keys,
exact integer endpoints and malformed envelope fields. The required native
build test speaks to the installed executable through a real Port and asserts
ready followed by exactly one terminal for split valid input, expired deadline,
fractional timeout and duplicate ID. No SDK service request is sent.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passed 254 checks (10 doctests, four
properties, 240 tests), one excluded interoperability test and 96.3% BEAM
coverage. Its selected native build rebuilt the pinned sources, ran CTest and
checked receipt tampering. A separate CMake build against the already verified
pinned static prefixes passed 179/179 CTest cases. A Debug
`WOTEX_SANITIZERS=ON` build with `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`
and `UBSAN_OPTIONS=halt_on_error=1` passed 168/168 selected
`native_(ipc|json|value|contract)` cases on macOS arm64. These local runs do
not establish Linux sanitizer coverage for the new slice.

| P02 input source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `39a10286f82841f74b323f98c5d225ccb1f5d6297d5b85538f19a8a27aa2be1f` |
| `priv/native/ipc.h` | `cd603dc0ad185f52cd23210e89107bebb2420dad40d4fb26faac22926e035e3a` |
| `priv/native/main.c` | `c388e31dbcee974bb032a9221aca73c76f5aecd1eaca9eceeab41e9461baabeb` |
| `priv/native/ipc_check.c` | `731617b3cc25db22036d557e54633e5eb99477b4592d940e58d908f26b61f55c` |
| `test/wotex/opcua/native/build_test.exs` | `a2a4d40235b7f6e5ea858634bba5baa8a59658f41deff14fcb94da9e7dbfefcb` |
| local normal CTest log | `30b15182ed0c19767c2ee50327aca1d67256c449413beef94db8ee47af4f8ebe` |
| local sanitizer CTest log | `dd8819b7bc7f05582a58c8fb804739d531bd009e44399d003f857d24e8a49932` |

This is a process-input and terminal-rejection slice, not acceptance of P02.
Per-operation parameter validation, persistent Session activation, namespace
acquisition, credits, responses, cancellation and all X-F17..F23/X-F49..F57
remain required. The current Python adapter still owns public network operations.

## P02 owner-side frame and clock projection

The next direct `main` slice adds `Native.Frame.admission/5` and `request/6`.
It maps the ready-native and separately captured owner-receive clocks to one
native deadline, rejects expiry and conversion overflow, caps the native timeout
to the remaining owner budget, and encodes a closed JSON request line with
checked integer, ID, operation, depth, node, string and total-byte limits.
The pure test covers exact boundary values and malformed inputs. The selected
native build test now uses this production encoder to send its split request to
the pinned executable; no native response or service success is claimed.

| Owner-side source/test | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/frame.ex` | `3be493df22a1d3601eda876e61d657ee0d134592287f7e8ca431f84484eead5a` |
| `test/wotex/opcua/native/frame_test.exs` | `4f277be341a886e01ee718b3eaf661da7a13114a4d71016071009161e1f03080` |
| `test/wotex/opcua/native/build_test.exs` | `5ffef075e9e4e402d7e6202d4a1f262a0389f857c7cd636f18a8fa5a3aef2564` |

The full `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 257 checks
(10 doctests, four properties, 243 tests), one interoperability exclusion and
96.3% BEAM coverage with a fresh pinned native build and CTest. P02 remains
open: its owner has no response relay, credits, activated Session or services.

## P02 terminal-only owner exchange

The subsequent internal `Native.Host.request/4` path allocates a BEAM-owned
uint64 generation, accepts only its original owner, sends the validated frame
through the independently owned runtime guardian, and waits under the original
deadline for one bounded terminal. `Native.Frame.terminal/2` accepts only the
matching generation, closed terminal/error fields, finite code/phase/effect
tables and optional uint32 status; malformed and extra output closes custody.
The real pinned-build test asserts `unsupported_protocol` from the actual C
process through `Native.Host`, while the pure decoder checks replay, duplicate,
unknown, truncated and oversized controls. A foreign caller cannot send a
request. A separate stalled native fault peer proves that a pending request
expires and custody reaps the process without an extra owner notification. The
host releases the process after its terminal and does not admit a
success-shaped service response.

| Terminal owner source/test | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/host.ex` | `04239b127b8c3939970fed217c1473c5a5a554b0630ad91eb9b387aadda6542e` |
| `lib/wotex/opcua/native/frame.ex` | `8058886abdef268433398e01c9a38748cd4f7b731305f4b69a722cfd5cc9110f` |
| `test/native/host_probe.c` | `a0c57fad8f3f5c75a98522977aed5e5121859759b1717371db72758798b1e3c9` |
| `test/wotex/opcua/native/host_test.exs` | `5e29db0b9a658c0e71eb91e6d69b2c324526297d3c9eaaf6433167b5ffd1c457` |
| `test/wotex/opcua/native/frame_test.exs` | `934234510742072dbc8af099015164ffe8bd2511eaf5e5b93d1ee76b2df563cc` |
| `test/wotex/opcua/native/build_test.exs` | `f8caab61924723ce86d380630efa85f6d4b8743f63372ddc1ae89e78989beb08` |

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed 259 checks
(10 doctests, four properties, 245 tests), one interoperability exclusion,
95.9% BEAM coverage, this real exchange and the fresh 179-case native CTest
build. P02 remains open: no persistent
Session, normal response relay, credits, services or independent native peer
interoperability is accepted.

## P02 native open shape rejection

The next C ingress slice validates the closed `open` parameter map before any
SDK network call. It recognizes exactly the three specified policy URIs and
`SignAndEncrypt`, bounds endpoint/ApplicationUri strings and session timeout,
checks all five certificate/key/trust/CRL fields as canonical base64 envelopes,
and checks anonymous, username or certificate user-token shapes. The C runner
tests all three allowed policy literals, downgrade/unknown fields, noncanonical
base64, token forms and timeout boundaries. The required native build test sends
a shape-valid and a downgraded `open` through the production BEAM encoder to
the actual executable. The former terminates `unsupported_protocol`; the
latter terminates `invalid_request`. The tiny test byte envelopes are not
certificates and no cryptographic or Session success is inferred.

| Open-shape source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `ba85da703e92b6291216d725cf228bec8dd1562bab7ad7cf031dc2713800bd0a` |
| `priv/native/ipc.h` | `a6aaccc565dfdf08d5301b5b89b77e772fd4144b3d53e05d13fd0a1869df9280` |
| `priv/native/ipc_check.c` | `8411cdc3610a137c54e79ce2672d63a2f7f6efb5fe55c00e771b5420d18a96f7` |
| `priv/native/main.c` | `af1f9df48859b97a71cf4b855fb8e133e739df6619e0f60991f0c073bfcc2cea` |
| `test/wotex/opcua/native/build_test.exs` | `f15b549e11d6b15741b84b497ac8370c4cc274812cd7930264e22d8358b812a1` |
| local normal CTest log | `e5e1d81009b01d4eb41d985c374c8d0f53754a22a58c47e3f14b1f3e2ae0eb88` |
| local sanitizer CTest log | `9f1a83e592e3d68bfcabf0f09ca7cc6540a86fc6563161b3a00715be9aa51745` |

The local static-prefix build passes 179/179 CTest cases; the macOS arm64
ASan/UBSan selected lane passes 168/168. The full
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed 259 checks (10 doctests,
four properties, 245 tests), one interoperability exclusion and 95.9% BEAM
coverage, including the fresh pinned build, docs and archive. P02 remains open,
and server identity,
certificate chain, CRL, private key and token security must be validated before
any native Session attempt.

## P02 initial credit and generation admission

The BEAM owner now emits the version-1 initial credit control with sequence one,
16 messages and 262144 bytes before its first request. Native ingress checks the
closed credit map and exact integer bounds, binds the first valid generation,
then rejects requests without the credit, mismatched generations and further
grants before output is consumed. It does not yet emit a normal response or
replenish consumed credits. The C driver exercises exact uint64 generation,
positive quantity ceilings, fractional/extra/duplicate fields and invalid
event kinds. The selected native build test sends the production credit and
request to the real C process and separately proves missing-credit rejection.

| Initial-credit source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `30287e937c00c2efac518128700d7ec8d67c2bd45f772275da5c5f8fcef90129` |
| `priv/native/ipc.h` | `cb4f64c492ff8fa8559ba6325d403e77a28ff489bd96912db22c9303ba50b5d6` |
| `priv/native/ipc_check.c` | `a7cf8af8dd73a642ac6f498f1e46c12f11d8e3c516370b264ab8cf9001f4a275` |
| `priv/native/main.c` | `9fb005cff6c2f7f75130a43db4fc0f2adc080e929adead5c46c8e9a7ea51821e` |
| `lib/wotex/opcua/native/frame.ex` | `a670f5dec7261e586e505228e8e6bb00ac154296914bcff456b148edacc9bb9b` |
| `lib/wotex/opcua/native/host.ex` | `5473b070b452a00b0af3ead77778641fa9fbfed926e29b86d0b8e4c31719cc74` |
| `test/wotex/opcua/native/frame_test.exs` | `d7d6907c311a1514aeec00a8b2e9157a199e93dd5345a29e7a72c0f5f421922e` |
| `test/wotex/opcua/native/build_test.exs` | `865ec93810607588238f5c81b4b18936017c1a8057dd6f614aa977cb8033b315` |
| local normal CTest log | `25735c8461c630f6ec668e10c8d76643d452bed92eb2e15e7ebf80d61b0c1d0d` |
| local sanitizer CTest log | `667665b1a6152c9691b077d0438f0b3ceac79c2788bedbc801ae1a6384d97f01` |

The local static-prefix build passes 179/179 CTest cases; the selected macOS
ASan/UBSan lane passes 168/168. `WOTEX_PATH_DEPS=1 mix check --no-retry` passed
260 checks (10 doctests, four properties, 246 tests), one interoperability
exclusion and 95.8% BEAM coverage, including the fresh pinned build, package
checks, docs and out-of-tree archive. P02 is still open: normal
credit consumption/replenishment, output queues and every service remain absent.

## Implemented Python-adapter interoperability

Real secure asyncua 2.0.1 peer: PASS for read, write/readback/restore, browse,
unknown-node failure, expired certificate, wrong host/URI, untrusted CA and
revoked certificate. Both sides use asyncua; this is a real wire/security proof,
not independent-stack interoperability or OPC Foundation certification.
Intermediate trust chains are outside the implemented security profile.

```sh
python3 -m venv /tmp/wotex-ua-test
/tmp/wotex-ua-test/bin/pip install -r priv/requirements.txt
/tmp/wotex-ua-test/bin/python test/interop/secure_peer.py /tmp/wotex-ua-fixture
# In a second terminal, after config.json exists:
WOTEX_PATH_DEPS=1 WOTEX_OPCUA_INTEROP_CONFIG=/tmp/wotex-ua-fixture/config.json mix test --include interop test/interop/asyncua_test.exs
```

Stop the explicitly started peer afterward. The fixture generates disposable
keys/certificates outside the repository; do not use them as operational trust.
The Python requirements are fully version-pinned. The Elixir gate does not
install Python dependencies; audit the optional environment separately with
`pip-audit --disable-pip --no-deps -r priv/requirements.txt`.

Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The native build tests under `test/wotex/opcua/native/` cover source admission,
workspace ownership, guarded commands, static build, dependency self-test and
receipt validation. Each completed build records separate source, build-code,
tool, option and artifact hashes in `wotex-native-build.json`; its command logs
are also hash-bound. The executable's one-tick SDK check is a dependency test,
not complete DataValue metadata or wire interoperability evidence.

The native secure Session, credit protocol, end-to-end 100 ns metadata and
independent asyncua/native workflow remain required implementation. Software
build/run entry points remain specified work. The interoperability command above
exercises the current Python runtime adapter.

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/asyncua_test.exs` | `d1eb6dae68bc989ccb5b1df7778d80c9512781cdcc2fb248d4c43b1a09567740` |
| `test/wotex/opcua/asyncua_test.exs` | `d36277d2fd7ec90e6fb393f19ee6730c600e6e83713190e83146dfce67182e6e` |
| `test/wotex/opcua/binary_test.exs` | `a173b9a4687c7965e4b45eab7809b066a428c0de26fe254f230e2fb7a8f23a9b` |
| `test/wotex/opcua/contract_test.exs` | `e9d677fe79d5d8b4fdb88d1d597b0d6bb3cb2bdbe2889a9cc4003432cb5e5f33` |
| `test/wotex/opcua/dependency_security_test.exs` | `3c45b778a241b2a577f9481c6a7ec08f4f8ec747f72a6d5e7deaf3265510e072` |
| `test/wotex/opcua/mapping_test.exs` | `2768c115820bcd56364bde5d2101bc13dc242fc92f5ca0a2c1b62b01e7812f93` |
| `test/wotex/opcua/port_test.exs` | `bf7dfcf70fa9afc680f07d4b861c56ecf954b01e8d280b12d7981849cc19cb48` |
| `test/wotex/opcua/value_test.exs` | `5c173dfdd5a27d60887064fe64041a3d5fd2434442bcd8abe431e00345f96089` |

## Native runtime custody

`test/wotex/opcua/native/custody_test.exs` executes the checked-in
`custody-contract-v1.json` cases using `priv/native/custody_check.c`. CTest repeats
those nine native cases during each actual SDK build. Assertions cover exact
fragmented bytes, simultaneous traffic, owner EOF with full pipes, stopped SDKs,
receiver loss, contained stderr, complete final output, blocked final drains,
group isolation and one shared cleanup deadline. The Linux test driver audits
orphan adoption independently of the guardian. A separate LeakSanitizer lane
retains the 500 ms SDK reap bound and explicitly reports instrumentation-only
post-main exit time; ordinary and ASan/UBSan timing lanes retain the 500 ms total
guardian bound. The [runtime custody contract](../../priv/native/runtime-guardian.md)
defines those separate acceptance conditions. These checks do not implement or
accept SDK frame credits, secure Sessions or OPC UA subscription ownership.

## BEAM native bootstrap

`native/ready_test.exs` executes every exact frame in `native-ready-v1.json`.
`native/executable_test.exs` exercises bounded file admission and SHA-256 identity.
`native/host_test.exs` compiles the real custody guardian with a separate C fault
peer, then asserts malformed readiness, fragmented output, failed executable
admission, stopped SDKs, owner death during hashing and readiness, post-startup
loss, and a suspended claimant's original deadline. A temporary Supervisor child
does not restart a failed host. Each started fault peer records both native
process identities and the tests check their absence after cleanup; the separate
C custody driver verifies direct-child reaping.

The required native build test starts the installed SDK helper and guardian
through `Native.Host` using their receipt digests. This is a real process-ready
integration check without an OPC UA endpoint or service. It does not accept a
secure Session, application data, subscription credit flow or remote cleanup.

## Native JSON syntax and numbers

`native/json_test.exs` compiles the reviewed parser and first-party adapter, then
executes every case in `native-json-v1.json` through the bounded command guardian.
The driver receives only the input frame and allocator size, and returns parsed
node counts, exact integer projections and IEEE-754 bit patterns. The tests
compare the complete declared output. Long frame boundaries use an exact prefix,
space count and suffix instead of repeated literal whitespace in the fixture.
The CTest self-test separately exercises strict flags and basic pool ownership.
Vendor tests reject missing, altered and symbolic source/license files. These
checks do not accept typed SDK construction, response serialization or services.

## Pure identity and reference structures

`standalone_contract_test.exs` executes WOP-F01 through F13 from
`contract-v1.json` through public `Binary` functions. The fixture input alone
reaches each decoder; the complete actual projection is compared with the
declared expectation. Test tags contain the fixture case, requirement IDs and
SHA-256 of the corpus bytes. `binary/names_test.exs` and
`binary/reference_test.exs` exercise exact masks and field order, all NodeId
kinds and NodeClasses, nullable/empty text, maximum string and URI lengths,
numeric overflow, every truncated field, invalid masks, and arbitrary byte
streams. Unconsumed tails remain byte-exact, including a tail larger than the
consumed identity limit. `typed_values_test.exs` exercises every supported
Variant type, null/empty arrays, dimensions, future numeric type preservation,
opaque binary/XML bodies, mixed-endian GUIDs and exact adjacent timestamp ticks.
DataValue assertions cover metadata masks, Bad/Uncertain status, present null
versus absent data, clamped/orphan fractions and the complete 1 MiB byte budget.
These checks cover the pure value and identity/reference structures of N02;
they do not accept SDK construction or Browse services.

## Native typed value conversion

`priv/native/fixtures/value-v1.json` contains 133 concrete JSON inputs and exact
Part 6 binary results or typed rejection results. The required native build
executes each case separately through `value_check` against pinned open62541
1.5.7. The constructor retains exact signed and unsigned integers, DateTime
100 ns ticks, explicit array shapes and encoded ExtensionObject identities.
The checker clears and overwrites the parser storage before SDK encoding, then
clears the SDK arena before serializing the projected result. Rejected inputs
must leave no result and restore the arena checkpoint.

`value_fault_check` adds 17 direct SDK structure cases. They cover invalid
parameters, unknown types, dimensions, finite floating values, UTF-8, namespace
conflicts, DataValue flags, allocation exhaustion and size boundaries. Maximum
1024-element arrays, 65536-byte strings and byte bodies, and an exactly 1 MiB
encoded Variant succeed. The corresponding excessive values fail. An input
constructor cannot mask these direct SDK faults by rejecting them first.

The source-bound native build receipt includes the corpus, both test drivers,
typed library sources and CTest log. The [value codec contract](../../priv/native/value-codec.md)
defines its arenas and result lifetimes. This evidence accepts conversion
primitives only. SDK network-decoder allocation checks, received reserved type
IDs, complete framed service output, native Session ownership and independent
peer metadata workflows remain separate required implementation.
