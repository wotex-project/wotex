import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { randomUUID } from "node:crypto"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
import test from "node:test"
import { hostRoot } from "./files.ts"
import { inspectFrontendSource } from "./frontend-style.ts"

const lint = (source: string, rule: string, extension = ".ts") => {
  const directory = mkdtempSync(resolve(hostRoot, "assets/.style-probe-"))
  const file = resolve(directory, `source${extension}`)
  try {
    writeFileSync(file, source)
    const result = spawnSync(
      resolve(hostRoot, "node_modules/.bin/biome"),
      ["lint", `--only=${rule}`, "--max-diagnostics=none", file],
      { cwd: hostRoot, encoding: "utf8" },
    )
    assert.equal(result.error, undefined)
    return { status: result.status, output: result.stdout + result.stderr }
  } finally {
    rmSync(directory, { recursive: true })
  }
}

test("installed Biome plugins reject all class forms, expressions and object methods", () => {
  for (const extension of [".ts", ".js", ".mjs", ".cjs"]) {
    for (const [source, message] of [
      ["class State {}", "factory function"],
      ["const State = class {}", "factory function"],
      ["export default class State {}", "factory function"],
      ["const run = function () {}", "function expression"],
      ["const state = { save() {} }", "object method shorthand"],
    ]) {
      const result = lint(source, "plugin", extension)
      assert.notEqual(result.status, 0, `${extension}: ${source}`)
      assert.ok(result.output.includes(message), result.output)
    }
  }
  assert.equal(
    lint(
      "const createState = () => ({ get value() { return 1 }, set value(next) { persist(next) }, save: () => 1 })",
      "plugin",
    ).status,
    0,
  )
})

test("test constructor exclusion is closed by the AST gate for arbitrary test classes", () => {
  assert.equal(lint("class ResizeObserver {}", "plugin", ".test.ts").status, 0)
  assert.equal(lint("class State {}", "plugin", ".test.ts").status, 0)
  assert.ok(
    inspectFrontendSource("assets/example.test.ts", "class State {}").some(
      (issue) => issue.rule === "no-classes",
    ),
  )
})

test("the installed nursery, style and complexity rule names fail on their actual syntax", () => {
  for (const [rule, source] of [
    ["nursery/useConsistentFunctionStyle", "function run() {}"],
    ["nursery/noThisOutsideOfClass", "const run = () => this.value"],
    ["style/noNestedTernary", "const value = first ? second : third ? fourth : fifth"],
    ["style/noParameterAssign", "const run = (value) => { value = 2 }"],
    ["complexity/useArrowFunction", "const run = function () { return 1 }"],
  ]) {
    const result = lint(source, rule)
    assert.notEqual(result.status, 0, result.output)
    assert.ok(result.output.includes(`lint/${rule}`), result.output)
  }
})

test("area selection is read-only and formatting never runs the style gate", () => {
  const directory = mkdtempSync(resolve(hostRoot, "assets/.style-probe-"))
  const file = resolve(directory, "source.ts")
  try {
    writeFileSync(file, "class State {}\n")
    const check = spawnSync(
      process.execPath,
      ["--experimental-strip-types", "tools/lint/check.ts", directory],
      {
        cwd: hostRoot,
        encoding: "utf8",
      },
    )
    assert.equal(check.status, 1)
    assert.ok(check.stderr.includes("no-classes"))
    const format = spawnSync(
      process.execPath,
      ["--experimental-strip-types", "tools/lint/format.ts", file],
      {
        cwd: hostRoot,
        encoding: "utf8",
      },
    )
    assert.equal(format.status, 0, format.stderr)
    assert.ok(!format.stdout.includes("violation"))
  } finally {
    rmSync(directory, { recursive: true })
  }
})

test("the standalone Storybook host inherits and executes the same plugins", () => {
  const relative = `priv/static/contract-assets/style-probe-${randomUUID()}.js`
  const file = resolve(hostRoot, "../storybook", relative)
  try {
    writeFileSync(file, "class State {}\n")
    const result = spawnSync(
      process.execPath,
      ["--experimental-strip-types", "tools/lint/biome-host.ts", "lint", "--only=plugin", relative],
      { cwd: hostRoot, encoding: "utf8" },
    )
    assert.notEqual(result.status, 0)
    assert.ok(
      (result.stdout + result.stderr).includes("factory function"),
      result.stdout + result.stderr,
    )
  } finally {
    rmSync(file)
  }
})
