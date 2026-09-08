---
spec:
  id: WTH.02
  title: "Implemented Thread profile"
  status: accepted
  version: 1.0.0
  owner: wotex-thread
  updated: 2026-09-09
---

# WTH.02 Implemented Thread profile

This is a local Wotex Form profile, not a standardized W3C Thread binding:
`thread+unix://controller-key/state` (also `/version`, `/network-name`, `/rloc16`).
Only `readproperty` is supported. Runtime requires a matching `target` and an
explicit Daemon `socket_path`. Application data uses a separate application
protocol over Thread; these management reads are not a generic Thread binding.

Dataset TLVs are at most 254 bytes. Duplicate types, including unknown types,
are rejected. Known fixed-width fields are checked and network names are valid
UTF-8, 1..16 bytes without ASCII controls. Unknown TLVs retain bytes and order.
Inspect hides entries; raw serialization is an explicit credential-bearing step.
Completeness checks field presence for active/pending context. Channel masks,
radio support, timestamps and full SDK semantics still require OpenThread.

Daemon sessions own their Unix socket in the calling process. Requests are an
enumerated command set; no shell or arbitrary CLI input is exposed. Output must
contain Done and no Error status, respect UTF-8 across packet boundaries, and
fit 8192 bytes. The socket line decoder enforces the packet allocation bound.
Failure/timeout closes the socket. Non-owner request/disconnect calls fail, and
owner termination closes the socket through OTP socket ownership. Dataset
changes, commissioning and daemon/radio lifecycle are excluded.

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
The consumer must run differential scenarios before replacing its implementation.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
