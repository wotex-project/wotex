# @wotex/lab-client

Generated client for the WoTEx Lab Workbench control API (0.1.0).
It implements the nine operations in the checked OpenAPI 3.2 projection and
has no runtime dependencies. Evidence and run reads and `queryMetrics`, which
reads the session room's attributed metric history, require an existing
session token. `startRun`, `cancelRun` and `approveDecision` also require a Workbench
host that opted into control mutations and a caller-chosen `idempotencyKey`;
retry a request with the same key to learn its outcome without repeating it.
The client cannot create sessions, write Properties or invoke an Action other
than a decision the session room granted.

```js
import { WotexLabClient } from "@wotex/lab-client";
const lab = new WotexLabClient({ baseUrl: "http://127.0.0.1:4000/api/v1" });
const { scenarios } = await lab.listScenarios();
```
