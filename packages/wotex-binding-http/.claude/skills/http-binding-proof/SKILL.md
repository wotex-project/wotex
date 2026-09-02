---
name: wotex-http-binding-proof
description: Apply when changing HTTP Form mapping, request or response values, the client port, credentials, JSON handling, or SSE lifecycle behavior.
---

# HTTP binding proof

1. Pin the Runtime transport callback and the exact WoT operation.
2. Identify whether the mapping comes from TD 1.1, an HTTP RFC, the SSE
   specification, or an explicitly non-conformant draft baseline.
3. Prove method, URI, representation, header, size, status, and client-return
   failure cells.
4. Prove credentials do not enter request, response, result, errors, handles,
   inspection output, or stream notifications.
5. Prove each successful stream open has one explicit close path.
6. Verify loading starts no application callback or process.
7. Run package, boundary, archive, and clean-tree gates.
