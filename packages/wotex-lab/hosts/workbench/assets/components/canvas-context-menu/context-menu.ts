export interface ContextMenuItem {
  id: string
  label: string
  disabled?: boolean
}

export const contextMenuItems = (
  kind: "thing" | "process" | "edge" | "metric" | "run",
  operations: ("read" | "observe" | "pause")[] = [],
  autoRefresh = false,
  hasOutcome = false,
): ContextMenuItem[] => {
  const inspect = {
    id: "inspect",
    label: {
      edge: "Configure connection",
      process: "Configure",
      metric: "Rename / sources",
      run: "Rename / sources",
      thing: "Inspect",
    }[kind],
  }
  if (kind === "run") {
    return [
      inspect,
      { id: "pin_open_run", label: "Open run", disabled: !hasOutcome },
      { id: "pin_remove", label: "Remove" },
    ]
  }
  if (kind === "metric") {
    return [
      inspect,
      { id: "pin_refresh", label: "Refresh" },
      { id: autoRefresh ? "pin_pause" : "pin_resume", label: autoRefresh ? "Pause" : "Resume" },
      { id: "pin_remove", label: "Remove" },
    ]
  }
  const labels = { read: "Read Property", observe: "Observe updates", pause: "Pause updates" }
  const controls =
    kind === "thing" || kind === "process"
      ? operations.map((id) => ({ id, label: labels[id] }))
      : []
  const sources =
    kind === "thing"
      ? [
          { id: "statistics", label: "Statistics" },
          { id: "sources", label: "Sources" },
        ]
      : []
  return [inspect, ...controls, ...sources, { id: "metrics", label: "Room metrics" }]
}
