import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { createHash } from "node:crypto"
import { readFileSync } from "node:fs"
import { createRequire } from "node:module"
import { dirname, join } from "node:path"

// Upstream has no fixed release for GHSA-gcqx-w48m-w2h4. The pnpm patch
// rejects prototype keys in both copy loops, including the unguarded target
// loop. Keep the registry finding visible, and qualify only these exact bytes
// before the normal low-severity audit accepts that remediated finding.
const requirePlugin = createRequire(import.meta.resolve("@sveltejs/vite-plugin-svelte"))
const root = dirname(requirePlugin.resolve("deepmerge/package.json"))
const expected = {
  "index.js": "7620e9ae9d35a34ad68c381086803915a37dbdc7701744983354c2f64d0c4d64",
  "dist/cjs.js": "ba17064616d9b1f0e7cb7c2ea33d2a457025299d247f746ac89e721c0cf97ecc",
  "dist/umd.js": "2d71dbf5b9dd3b2b2e0559cd63660d1d6b61aac6b1d53e232914ae1bc9fb2723",
}

assert.equal(JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version, "4.3.1")
for (const [file, digest] of Object.entries(expected)) {
  const actual = createHash("sha256")
    .update(readFileSync(join(root, file)))
    .digest("hex")
  assert.equal(
    actual,
    digest,
    `deepmerge patch changed: ${file}; review before accepting its advisory`,
  )
}

const proof = spawnSync(
  process.execPath,
  ["--experimental-strip-types", "--test", "test/frontend/dependency-security.test.ts"],
  { stdio: "inherit" },
)
assert.equal(proof.status, 0, "installed merger security and compatibility proof failed")
console.log(
  "Verified the installed local patch for GHSA-gcqx-w48m-w2h4; auditing all other advisories",
)
const audit = spawnSync("pnpm", ["audit", "--json"], { encoding: "utf8" })
assert.ok(!audit.error && (audit.status === 0 || audit.status === 1), audit.stderr)
const report = JSON.parse(audit.stdout)
assert.ok(report.advisories && report.metadata?.vulnerabilities && !report.error)
console.log(audit.stdout)
const advisories = Object.values(report.advisories) as {
  github_advisory_id: string
  module_name: string
  findings: { version: string }[]
}[]
const total = Object.values(report.metadata.vulnerabilities).reduce((sum: number, count) => {
  assert.ok(Number.isInteger(count) && Number(count) >= 0)
  return sum + Number(count)
}, 0)
assert.equal(total, advisories.length, "registry audit counts do not match its findings")
assert.ok(audit.status === 0 || advisories.length > 0, "registry audit failed without findings")
for (const advisory of advisories) {
  assert.ok(
    advisory.github_advisory_id === "GHSA-gcqx-w48m-w2h4" &&
      advisory.module_name === "deepmerge" &&
      advisory.findings.length > 0 &&
      advisory.findings.every((finding) => finding.version === "4.3.1"),
    `unremediated dependency advisory: ${advisory.github_advisory_id}`,
  )
}
