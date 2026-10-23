import { spawnSync } from "node:child_process"
import { resolve } from "node:path"
import { hostRoot } from "./files.ts"

const [directory, ...biomeArguments] = process.argv.slice(2)

if (!directory) {
  process.stderr.write("usage: biome-host.ts <host-directory> <biome-command> [options]\n")
  process.exitCode = 1
} else {
  const result = spawnSync(resolve(hostRoot, "node_modules/.bin/biome"), biomeArguments, {
    cwd: resolve(hostRoot, directory),
    stdio: "inherit",
  })

  if (result.error) {
    throw result.error
  }
  process.exitCode = result.status ?? 1
}
