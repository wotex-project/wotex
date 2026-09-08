# Thread primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract above
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and evidence still requiring hardware or SDK execution.

- [OpenThread v2026.09.0 dataset API](https://github.com/openthread/openthread/blob/v2026.09.0/include/openthread/dataset.h).
- [OpenThread dataset validation](https://github.com/openthread/openthread/blob/v2026.09.0/src/core/meshcop/dataset.cpp).
- [OpenThread daemon](https://openthread.io/platforms/co-processor/ot-daemon).
- [Co-processor architectures](https://openthread.io/platforms/co-processor).
- [Dataset CLI restrictions](https://openthread.io/reference/cli/concepts/dataset).
- [Operational dataset API](https://openthread.io/reference/group/api-operational-dataset).

Research searched standards/revision availability, wire/address rules, transport
ownership, security and interoperability gaps, then reviewed upstream APIs.
Stop reason: consequential design claims have primary evidence or explicit
access limits. No physical or secure-stack execution was performed by research.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

## Software-contract review, 2026-09-08

Pin every native component to `5c8c318627954c99cd1a957a290bbd4b1027d04b`
(OpenThread v2026.09.0):

- [Dataset API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/dataset.h)
  declares otDatasetIsValid with OperationalDatasetTlvs and an active flag.
  SendMgmtActiveSet/PendingSet immediate success means submission; their callback
  determines the exchange outcome. Local SetActiveTlvs is a different operation.
- [Commissioner API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/commissioner.h),
  [Joiner API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/joiner.h)
  and [PSKd/discerner validation](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/core/meshcop/meshcop.cpp)
  define explicit roles, callback ownership and credential grammar.
- [Simulation platform](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/examples/platforms/simulation/README.md)
  and [CMake options](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/etc/cmake/options.cmake)
  define RCP/FTD software builds. The daemon documentation's forkpty radio URL
  provides a real POSIX-host/simulated-RCP seam; fixture paths must come from the
  actual selected build output, not an assumed output/simulation directory.

The new C bridge owns its own host instance and radio connection. This is an
architectural choice: a library cannot obtain a live C pointer into a separate
borrowed ot-daemon process. Production SDK management and the existing read-only
CLI socket profile remain separate explicit adapters. No unreviewed Thread
normative or physical-radio conformance claim follows from the source review.
