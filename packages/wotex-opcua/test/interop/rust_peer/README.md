# Independent Rust interoperability peer

This test-only executable runs an OPC UA server on async-opcua 0.19.0. It is
independent of the production client's open62541 stack. It supplies Browse
continuation, Cancel and Republish observations plus the positive X-F30 through
X-F38 policy/token workflows asserted by `rust_peer_test.exs`. Its continuation
capacity is deliberately above the client's 64-handle Session limit so that
boundary is measured at the peer. The fixture
exposes all three required SignAndEncrypt policies,
anonymous/username/certificate tokens, the full scalar set consumed by the
Runtime adapter, arrays for every non-null projected type, writable arrays for
every type accepted by the Runtime Write mapper, a typed addition Method, live
resource counters and a counted next-notification fault. That fault either
retains the withheld notification for Republish or discards it. This is not a
general-purpose or production server profile.

`Cargo.lock` fixes the dependency graph. The software build copies this whole
directory to its explicit workspace, performs one locked fetch, and then builds
offline with warnings denied. Local `target/` output is ignored and is never
part of the copied or hashed project.

## Vendored patches

`vendor/async-opcua-server` and `vendor/async-opcua-nodes` are the crates.io
0.19.0 sources from upstream commit
`9ad28fc011002398f2e8a95696a50408a14531d9`. They remain licensed MPL-2.0 as
declared by their Cargo manifests. The fixture patches:

- implement the standard Cancel service for active asynchronous requests and
  expose aggregate Cancel, browse-continuation, subscription, MonitoredItem and
  subscription create/delete request counts to fixture methods;
- count successful secure-channel token renewals and provide a short-lifetime
  variant for renewal tests;
- count Write service requests and provide a post-write invalid-Session response
  for no-replay tests;
- inject a missing value or one status into the next completed Read result
  without replacing the Read service;
- expose a counted fault that withholds the next notification while preserving
  real Publish and Republish service traffic;
- expose isolated response-envelope faults for subscription creation,
  MonitoredItem creation and both cancellation services, after real server
  resources have been acquired or released;
- expose one-shot Publish integrity faults for duplicate and conflicting
  sequences, oversized gaps, client-handle identity, StatusChange and
  acknowledgement validation;
- advertise X.509 user tokens with the endpoint's security policy so the
  signature algorithm used by the client and verifier is identical;
- keep address-space reference buckets in insertion order;
- return queued BrowseNext pages from the front;
- disable postcard's unused default heapless feature so the lock contains no
  target-inactive, unmaintained `atomic-polyfill` dependency.

The unmodified crates remain registry dependencies. Only these two patched
crates are overridden by `[patch.crates-io]`.

The peer accepts the exact copied client leaf through async-opcua's fixture
trust switch after certificate validation. That setting is deliberately scoped
to this disposable interoperability process and is not production trust policy.

The RustSec audit has one explicit exception: `RUSTSEC-2023-0071` affects the
`rsa` crate and has no patched release. RustSec's stated workaround permits
local use on a non-compromised computer. This fixture binds only to
`127.0.0.1`, uses disposable keys, accepts no remote connection and is never a
runtime or shipped server. The software lane ignores exactly that advisory;
every other RustSec vulnerability or warning still fails `cargo audit`.
