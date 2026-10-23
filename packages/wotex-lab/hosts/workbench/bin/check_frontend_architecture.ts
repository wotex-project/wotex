import { readdir, readFile, writeFile } from "node:fs/promises"
import { basename, dirname, join, relative, resolve } from "node:path"
import { formatFunctionSpacing, inspectFrontendSource } from "./frontend_architecture.ts"

const root = resolve(import.meta.dirname, "..")

const filesWithin = async (directory: string): Promise<string[]> => {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = await Promise.all(
    entries.map((entry) =>
      entry.isDirectory()
        ? filesWithin(join(directory, entry.name))
        : [join(directory, entry.name)],
    ),
  )
  return files.flat()
}

const files = [
  ...(await filesWithin(join(root, "assets"))),
  ...(await filesWithin(join(root, "bin"))),
]
const sources = files.filter((file) => /\.(ts|svelte|mjs|cjs)$/.test(file))
const errors: string[] = []

for (const file of sources) {
  const name = relative(root, file)
  let source = await readFile(file, "utf8")
  if (process.argv.includes("--fix")) {
    const formatted = formatFunctionSpacing(name, source)
    if (formatted !== source) {
      await writeFile(file, formatted)
      source = formatted
    }
  }
  errors.push(
    ...inspectFrontendSource(name, source).map(
      (issue) => `${name}:${issue.line}: ${issue.message}`,
    ),
  )
  if (name.endsWith(".svelte") && !name.startsWith("assets/catalogue/")) {
    const folder = dirname(name)
    if (basename(folder) !== basename(name, ".svelte")) {
      errors.push(`${name}: each component owns its directory`)
    }
    const story = files.some(
      (candidate) =>
        dirname(relative(root, candidate)) === folder && candidate.endsWith(".stories.ts"),
    )
    if (!story) {
      errors.push(`${name}: missing colocated Storybook stories`)
    }
  }
}

if (errors.length) {
  process.stderr.write(`${errors.join("\n")}\n`)
  process.exitCode = 1
} else {
  process.stdout.write(
    `frontend architecture: ${sources.length} files; arrow functions, spacing, aliases, events and stories verified\n`,
  )
}
