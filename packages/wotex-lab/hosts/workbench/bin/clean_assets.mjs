import { rm } from "node:fs/promises"

const staticRoot = new URL("../priv/static/", import.meta.url)

await rm(new URL(".vite/", staticRoot), { force: true, recursive: true })
await rm(new URL("assets/", staticRoot), { force: true, recursive: true })
