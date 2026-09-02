---
name: wotex-runtime-proof
description: Apply when adding a ConsumedThing, ExposedThing, Form-selection, transport-port, credential-port, or subscription behavior.
---

# Runtime proof

1. Pin the owning runtime requirement and TD 1.1 operation.
2. Map the pure plan, credential request, transport request, and result boundary.
3. Prove unsupported and unavailable cells fail explicitly.
4. Test zero, one, and multiple process instances when a child spec exists.
5. Verify loading the application starts no callback.
6. Prove errors and state contain no credential material.
7. Run the package and clean-consumer gates.
