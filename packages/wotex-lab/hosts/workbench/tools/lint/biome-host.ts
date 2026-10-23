import { spawnSync } from "node:child_process"
import { resolve } from "node:path"
import { hostRoot } from "./files.ts"

const result = spawnSync(resolve(hostRoot, "node_modules/.bin/biome"), process.argv.slice(2), {
  cwd: resolve(hostRoot, "../storybook"),
  stdio: "inherit",
})

if (result.error) {
  throw result.error
}
process.exitCode = result.status ?? 1
