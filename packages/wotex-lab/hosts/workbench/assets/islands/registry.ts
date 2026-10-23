import type { IslandLoader } from "$lib/islands/types.ts"

export const islandRegistry = {
  canvas: () => import("$lib/islands/canvas/canvas.svelte"),

  tabs: () => import("$lib/islands/tabs/tabs.svelte"),

  "data-grid": () => import("$lib/islands/data-grid/data-grid.svelte"),

  chart: () => import("$lib/islands/chart/chart.svelte"),
} satisfies Record<string, IslandLoader>

export type IslandComponentName = keyof typeof islandRegistry

export const islandLoader = (name: string): IslandLoader | undefined =>
  islandRegistry[name as IslandComponentName]
