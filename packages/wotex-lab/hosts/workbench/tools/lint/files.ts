import { readdir, stat } from "node:fs/promises"
import { resolve } from "node:path"

export const hostRoot = resolve(import.meta.dirname, "../..")

const filesWithin = async (path: string): Promise<string[]> => {
  const information = await stat(path)
  if (!information.isDirectory()) {
    return /\.(ts|svelte|mjs|cjs|js)$/.test(path) ? [path] : []
  }
  const entries = await readdir(path)
  const files = await Promise.all(entries.map((entry) => filesWithin(resolve(path, entry))))
  return files.flat()
}

export const sourceFiles = async (paths: string[] = []) => {
  const selected = paths.length
    ? paths
    : ["assets", "tools", ".storybook", "vite.config.ts"]
  return [
    ...new Set(
      (await Promise.all(selected.map((path) => filesWithin(resolve(hostRoot, path))))).flat(),
    ),
  ].sort()
}
