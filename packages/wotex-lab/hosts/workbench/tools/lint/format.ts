import { readFile, writeFile } from "node:fs/promises"
import { relative } from "node:path"
import { hostRoot, sourceFiles } from "./files.ts"
import { formatSpacing } from "./spacing.ts"

const files = await sourceFiles(process.argv.slice(2))
let changed = 0

for (const file of files) {
  const source = await readFile(file, "utf8")
  const formatted = formatSpacing(relative(hostRoot, file), source)
  if (source !== formatted) {
    await writeFile(file, formatted)
    changed += 1
  }
}
process.stdout.write(`frontend spacing: ${files.length} files, ${changed} formatted\n`)
