import type { ResolveHookSync } from "node:module"

const aliases: Record<string, URL> = {
  "$lib/": new URL("../../assets/", import.meta.url),
  "$seeds/": new URL("../../priv/seeds/", import.meta.url),
}

export const resolve: ResolveHookSync = (specifier, context, nextResolve) => {
  const prefix = Object.keys(aliases).find((value) => specifier.startsWith(value))
  const target = prefix ? new URL(specifier.slice(prefix.length), aliases[prefix]).href : specifier
  return nextResolve(target, context)
}
