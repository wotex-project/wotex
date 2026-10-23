import { basename, dirname, join } from "node:path"

export const inspectComponentLayout = (file: string, files: ReadonlySet<string>): string[] => {
  if (!file.endsWith(".svelte") || file.startsWith("assets/catalogue/")) {
    return []
  }
  const directory = dirname(file)
  const name = basename(file, ".svelte")
  if (files.has(join(directory, `${name}.stories.ts`))) {
    return []
  }
  const owner = join(dirname(directory), `${basename(directory)}.svelte`)
  const story = join(dirname(directory), `${basename(directory)}.stories.ts`)
  if (files.has(owner) && files.has(story)) {
    return []
  }
  return ["Colocate rendered stories with the component or its owning private-child surface."]
}
