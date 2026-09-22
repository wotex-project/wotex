import type { IslandLoader } from "./types.js"

export const islandRegistry = {
  tabs: () => import("./tabs.svelte"),
  "data-grid": () => import("./data-grid.svelte"),
  chart: () => import("./chart.svelte"),
} satisfies Record<string, IslandLoader>

export type IslandComponentName = keyof typeof islandRegistry

export const islandLoader = (name: string): IslandLoader | undefined =>
  islandRegistry[name as IslandComponentName]
