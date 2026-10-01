---
name: transport-lifecycle
description: Change Runtime planning, credential or transport ports, protocol Form mapping or subscription lifecycle. Use for deadlines, receiver ownership, stream cleanup and redaction; exclude pure value codecs and archive-only checks.
user-invocable: false
---

# Test interaction ownership

Input: the changed operation, port callbacks, handle and process owners.
Output: executable tests of the affected request or stream paths, with ownership
and failure behavior consistent across the public boundary.

Read the affected Runtime, binding or adapter package guidance and owning
specification. Trace the pure plan, credential request, transport call and
returned result. Identify who owns deadlines, admission, handles, report
receivers and cancellation before changing a callback.

Test unsupported operation, direction, security and binding cells explicitly.
Check that malformed client returns, raised callbacks, timeout and closed
handles become the documented errors without exposing credentials or external
exception text. Test credential absence from values, state, inspection, errors
and notifications; a textual search cannot establish redaction.

For a stream, test open, early reports, delivery bounds, receiver death,
cancellation, startup failure and cleanup as affected. Every successful open
must have an owned close path; validate multiple independent instances where
the mechanism has a child specification.

For HTTP changes, inspect method defaults, URI and header admission, framing
fields, bounded JSON and response statuses. For SSE, test the exact opaque
handle and stop operation without an implicit request. For MQTT changes,
inspect Control Packet mapping, broker href versus Form topics, retained-read
requirements, QoS, Topic Name/Filter admission and deadline propagation.
Use the existing operation and client-lifecycle tests in each binding.

For native adapters, use the existing scripted bridge and fault tests for the
changed Port boundary. Select native or interop lanes only within the scope
allowed by `AGENTS.md`. Run focused tests and then the applicable package
validation; identify which paths were actually exercised.
