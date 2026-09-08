# @wotex/lab-client

Generated read-only client for the WoTEx Lab Workbench control API (0.1.0).
It implements the four operations in the checked OpenAPI 3.2 projection and
has no runtime dependencies. Evidence reads require an existing session token;
the client cannot create sessions, run experiments, write Properties or invoke Actions.

```js
import { WotexLabClient } from "@wotex/lab-client";
const lab = new WotexLabClient({ baseUrl: "http://127.0.0.1:4000/api/v1" });
const { scenarios } = await lab.listScenarios();
```
