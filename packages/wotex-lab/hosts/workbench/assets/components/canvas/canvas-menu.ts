import type { Node } from "@xyflow/svelte"

export type CanvasMenuKind = "edge" | "run" | "metric" | "process" | "thing"

export const menuLabels: Record<CanvasMenuKind, string> = {
  edge: "Connection actions",
  run: "Run result actions",
  metric: "Metric actions",
  process: "Thing actions",
  thing: "Thing actions",
}

export const resolveMenuKind = (kind: "node" | "edge" | undefined, node?: Node): CanvasMenuKind => {
  if (kind === "edge") {
    return "edge"
  }
  if (node?.type === "run_result") {
    return "run"
  }
  if (node?.type === "metric") {
    return "metric"
  }
  return node?.data.kind === "process" ? "process" : "thing"
}
