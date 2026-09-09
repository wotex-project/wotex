# Thread primary sources

The selected OpenThread SDK is v2026.09.0 commit
`5c8c318627954c99cd1a957a290bbd4b1027d04b`. Exact archive, Mbed TLS/framework and
source-fix hashes are in `priv/openthread/dependencies.json` and
[WTH.13](../specs/WTH.13-native-backend.md). This is SDK-derived software behavior;
the complete Thread normative text is not reviewed and certification is not claimed.

- [Dataset API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/dataset.h)
  defines TLV semantic validation and distinct local installation versus management
  exchange. Immediate submission and asynchronous outcome are different results.
- [Commissioner](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/commissioner.h)
  and [Joiner](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/joiner.h)
  define role callbacks, exact joiner admission and joiner completion. Neither
  commissioner activity nor Joiner success alone establishes attachment.
- [PSKd/discerner implementation](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/core/meshcop/meshcop.cpp)
  grounds credential grammar and the pinned full-width discerner fix.
- [POSIX platform](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/posix/README.md),
  [simulation platform](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/examples/platforms/simulation/README.md)
  and [CMake options](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/etc/cmake/options.cmake)
  define separate host/RCP ownership and compiled simulated peers.
- [Daemon architecture](https://openthread.io/platforms/co-processor/ot-daemon)
  defines the separate daemon process. A borrowed socket exposes the documented
  read-only CLI profile, not a live SDK pointer or permission to mutate its state.

The first-party host is C++17 using the SDK's C API. Generic orchestration and
assertions belong to Mix/ExUnit, while SDK-required generation may use build-time
Python. Thread carries IPv6; application temperature/light operations compose
an explicit CoAP client and real peer, without a fabricated Thread property API,
exactly-once delivery or a universal application payload ceiling.

W3C [TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
owns Thing Description semantics. A package-defined protocol Form profile is
not W3C certification. Source review supports API choices; execution evidence
belongs to [executable-evidence.md](executable-evidence.md). Native .13 specifies
library policy for limits, credits, error classes and ownership, not extra
protocol-standard guarantees.
