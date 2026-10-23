import { readFile } from "node:fs/promises"
import { relative } from "node:path"
import { hostRoot, sourceFiles } from "./files.ts"
import { inspectFrontendSource } from "./frontend-style.ts"
import { inspectComponentLayout } from "./layout.ts"

const paths = process.argv.slice(2)
const allFiles = await sourceFiles()
const inventory = new Set(allFiles.map((file) => relative(hostRoot, file)))
const files = paths.length ? await sourceFiles(paths) : allFiles
let violations = 0

for (const file of files) {
  const name = relative(hostRoot, file)
  const source = await readFile(file, "utf8")
  try {
    const issues = inspectFrontendSource(name, source)
    for (const { path, line, column, rule, message } of issues) {
      process.stderr.write(`${path}:${line}:${column} ${rule}: ${message}\n`)
    }
    const layout = inspectComponentLayout(name, inventory)
    layout.forEach((message) => {
      process.stderr.write(`${name}:1:1 component-stories: ${message}\n`)
    })
    violations += issues.length + layout.length
  } catch (error) {
    process.stderr.write(`${name}:1:1 parse: ${String(error)}\n`)
    violations += 1
  }
}
process.stdout.write(`frontend style: ${files.length} files, ${violations} violations\n`)
process.exitCode = violations ? 1 : 0
