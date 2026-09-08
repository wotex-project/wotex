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
