import assert from "node:assert/strict"
import { readdir, readFile } from "node:fs/promises"
import { join } from "node:path"
import { gzipSync } from "node:zlib"

interface ManifestEntry {
  dynamicImports?: string[]
  file: string
  imports?: string[]
  isEntry?: boolean
}

const root = new URL("../../priv/static/", import.meta.url)
const manifest: Record<string, ManifestEntry> = JSON.parse(
  await readFile(new URL(".vite/manifest.json", root), "utf8"),
)
const files = await readdir(new URL("assets/", root))
const entry = manifest["assets/app.ts"]
const storybookEntry = manifest["assets/storybook.ts"]
const documentationEntry = manifest["assets/documentation.ts"]

assert.ok(entry?.isEntry, "assets/app.ts must be a production entry")
assert.ok(storybookEntry?.isEntry, "assets/storybook.ts must be the qualification entry")
assert.ok(documentationEntry?.isEntry, "documentation must have its own inert entry")
assert.equal(Object.values(manifest).filter((item) => item.isEntry).length, 3)
assert.deepEqual(
  documentationEntry.imports ?? [],
  [],
  "documentation must not load the island runtime",
)
assert.deepEqual(
  documentationEntry.dynamicImports ?? [],
  [],
  "documentation must remain standalone",
)
assert.deepEqual(
  entry.imports,
  storybookEntry.imports,
  "both hosts must share the real island hook",
)
const [hookName] = entry.imports ?? []
assert.ok(hookName, "the production entry must import the island hook")
const hook = manifest[hookName]
assert.ok((hook?.dynamicImports ?? []).length >= 3, "registered islands must remain split")
assert.ok(
  files.every((file) => !file.endsWith(".map")),
  "source maps are forbidden",
)

for (const file of files) {
  const bytes = await readFile(join(new URL("assets/", root).pathname, file))
  assert.ok(bytes.length <= 196_608, `${file} exceeds the raw production budget`)
  assert.ok(gzipSync(bytes).length <= 65_536, `${file} exceeds the gzip production budget`)

  if (file.endsWith(".js")) {
    const source = bytes.toString("utf8")
    assert.ok(!/sourceMappingURL/i.test(source), `${file} has forbidden runtime content`)
    if (file !== storybookEntry.file.replace("assets/", "")) {
      assert.ok(!/storybook/i.test(source), `${file} leaks qualification code into production`)
    }
    assert.ok(
      !/(?:fetch|import)\s*\(\s*["']https?:\/\//i.test(source),
      `${file} has a remote runtime load`,
    )
    assert.ok(!/\beval\s*\(/.test(source), `${file} contains eval`)
  }
}

console.log(
  `assets: ${files.length} local content-hashed files, three isolated entries, budgets satisfied`,
)
