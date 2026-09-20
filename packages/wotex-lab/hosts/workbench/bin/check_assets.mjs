import assert from "node:assert/strict"
import { gzipSync } from "node:zlib"
import { readFile, readdir } from "node:fs/promises"
import { join } from "node:path"

const root = new URL("../priv/static/", import.meta.url)
const manifest = JSON.parse(await readFile(new URL(".vite/manifest.json", root), "utf8"))
const files = await readdir(new URL("assets/", root))
const entry = manifest["assets/app.ts"]
const storybookEntry = manifest["assets/storybook.ts"]

assert.ok(entry?.isEntry, "assets/app.ts must be a production entry")
assert.ok(storybookEntry?.isEntry, "assets/storybook.ts must be the qualification entry")
assert.equal(Object.values(manifest).filter((item) => item.isEntry).length, 2)
assert.deepEqual(entry.imports, storybookEntry.imports, "both hosts must share the real island hook")
const hook = manifest[entry.imports[0]]
assert.ok((hook?.dynamicImports ?? []).length >= 3, "registered islands must remain split")
assert.ok(files.every((file) => !file.endsWith(".map")), "source maps are forbidden")

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
    assert.ok(!/(?:fetch|import)\s*\(\s*["']https?:\/\//i.test(source), `${file} has a remote runtime load`)
    assert.ok(!/\beval\s*\(/.test(source), `${file} contains eval`)
  }
}

console.log(`assets: ${files.length} local content-hashed files, two isolated entries, budgets satisfied`)
