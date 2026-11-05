import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { delimiter, join } from "node:path"
import test from "node:test"

const patched = {
  github_advisory_id: "GHSA-gcqx-w48m-w2h4",
  module_name: "deepmerge",
  findings: [{ version: "4.3.1" }],
}

const report = (advisories: object[], count = advisories.length) => ({
  advisories: Object.fromEntries(advisories.map((advisory, index) => [index, advisory])),
  metadata: { vulnerabilities: { info: 0, low: count, moderate: 0, high: 0, critical: 0 } },
})

const check = (body: object, status: number) => {
  const directory = mkdtempSync(join(tmpdir(), "wotex-dependency-audit-"))
  try {
    // Only the registry port is replaced. Execute the actual installed-byte
    // checks and merger regressions before it evaluates this synthetic reply.
    writeFileSync(
      join(directory, "pnpm"),
      '#!/bin/sh\nprintf \'%s\' "$WOTEX_TEST_AUDIT_REPORT"\nexit "$WOTEX_TEST_AUDIT_STATUS"\n',
      { mode: 0o700 },
    )
    return spawnSync(
      process.execPath,
      ["--experimental-strip-types", "tools/assets/dependencies.ts"],
      {
        encoding: "utf8",
        env: {
          ...process.env,
          PATH: directory + delimiter + process.env.PATH,
          WOTEX_TEST_AUDIT_REPORT: JSON.stringify(body),
          WOTEX_TEST_AUDIT_STATUS: String(status),
        },
      },
    )
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

test("the dependency checker accepts a clean report or the byte-verified patched finding", () => {
  for (const [body, status] of [
    [report([]), 0],
    [report([patched]), 1],
  ] as const) {
    const result = check(body, status)
    assert.equal(result.status, 0, result.stdout + result.stderr)
  }
})

test("the dependency checker refuses new advisories, other versions and registry failures", () => {
  const unknown = { ...patched, github_advisory_id: "GHSA-new-advisory", severity: "critical" }
  for (const [body, status] of [
    [report([patched, unknown]), 1],
    [report([{ ...patched, findings: [{ version: "4.3.2" }] }]), 1],
    [report([{ ...patched, module_name: "another-package" }]), 1],
    [report([patched], 2), 1],
    [{ error: { code: "REGISTRY_UNAVAILABLE" } }, 1],
    [report([]), 2],
  ] as const) {
    const result = check(body, status)
    assert.notEqual(result.status, 0, result.stdout + result.stderr)
  }
})
