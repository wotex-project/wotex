import type { JsonValue } from "./types.js"

export interface CanvasNode extends Record<string, unknown> {
  id: string
  kind: "thing" | "process" | "entry"
  title: string
  identity: string
  value: string
  unit: string
  status: string
  detail: string
  x: number
  y: number
}

export interface CanvasEdge {
  id: string
  source: string
  target: string
  label: string
  kind: "input" | "proposal"
  target_handle: "temperature" | "power" | "input"
}

export interface MetricSeries { name: string; points: [number, number | null][] }
export interface CanvasPin extends Record<string, unknown> {
  id: string; title: string; metric: string; source: string; range: string; unit: string
  aggregation: string; state: string; auto_refresh: boolean; end_ms: number; series: MetricSeries[]
  x: number; y: number; width: number; height: number
}
export interface CanvasViewport { x: number; y: number; zoom: number }

const nodeFields = ["id", "kind", "title", "identity", "value", "unit", "status", "detail", "x", "y"]
const edgeFields = ["id", "source", "target", "label", "kind", "target_handle"]
const textLimits = { id: 128, title: 128, identity: 256, value: 128, unit: 32, status: 32, detail: 128 }
const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
const exact = (value: Record<string, unknown>, keys: string[]) =>
  Object.keys(value).length === keys.length && keys.every((key) => key in value)
const text = (value: unknown, limit: number): value is string =>
  typeof value === "string" && new TextEncoder().encode(value).length <= limit
const identifier = (value: unknown): value is string =>
  text(value, 128) && /^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(value)
const coordinate = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= 20000

export function validateCanvas(payload: Record<string, JsonValue>): void {
  const { nodes, edges } = payload
  if (!Array.isArray(nodes) || nodes.length > 32 || !Array.isArray(edges) || edges.length > 64)
    throw new Error("invalid canvas limits")
  const ids = new Set<string>()
  for (const node of nodes) {
    if (!record(node) || !exact(node, nodeFields) || !identifier(node.id) || ids.has(node.id) ||
      !["thing", "process", "entry"].includes(String(node.kind)) ||
      !Object.entries(textLimits).every(([key, limit]) => text(node[key], limit)) ||
      !coordinate(node.x) || !coordinate(node.y)) throw new Error("invalid canvas node")
    ids.add(node.id)
  }
  const edgeIds = new Set<string>()
  for (const edge of edges) {
    if (!record(edge) || !exact(edge, edgeFields) || !identifier(edge.id) || edgeIds.has(edge.id) ||
      !identifier(edge.source) || !identifier(edge.target) ||
      !ids.has(edge.source) || !ids.has(edge.target) || !text(edge.label, 128) ||
      !["input", "proposal"].includes(String(edge.kind)) ||
      !["temperature", "power", "input"].includes(String(edge.target_handle)))
      throw new Error("invalid canvas edge")
    edgeIds.add(edge.id)
  }
  const pins = payload.pins ?? []
  if (!Array.isArray(pins) || pins.length > 16) throw new Error("invalid canvas pins")
  for (const pin of pins) {
    if (!record(pin) || !exact(pin, ["id", "title", "metric", "source", "range", "unit", "aggregation", "state", "auto_refresh", "end_ms", "series", "x", "y", "width", "height"]) ||
      !identifier(pin.id) || ids.has(pin.id) || !identifier(pin.metric) ||
      !text(pin.title,128) || !text(pin.source,64) || !text(pin.unit,32) ||
      !text(pin.aggregation,64) || !text(pin.state,64) || !["5m","15m","1h"].includes(String(pin.range)) ||
      typeof pin.auto_refresh !== "boolean" || !Number.isSafeInteger(pin.end_ms) || !coordinate(pin.x) || !coordinate(pin.y) ||
      !between(pin.width,300,800) || !between(pin.height,200,600) ||
      !Array.isArray(pin.series) || pin.series.length > 8) throw new Error("invalid canvas pin")
    const names = new Set<string>()
    for (const series of pin.series) {
      if (!record(series) || !exact(series,["name","points"]) || !text(series.name,128) || names.has(series.name) ||
        !Array.isArray(series.points) || series.points.length > 61 ||
        !series.points.every(p => Array.isArray(p) && p.length===2 && between(p[0],-1e100,1e100) &&
          (p[1] === null || between(p[1],-1e100,1e100)))) throw new Error("invalid pin series")
      names.add(series.name)
    }
    ids.add(pin.id)
  }
  const view = payload.view ?? []
  if (!Array.isArray(view) || view.length > 1 || !view.every(v => record(v) && exact(v,["x","y","zoom"]) &&
    between(v.x,-100000,100000) && between(v.y,-100000,100000) && between(v.zoom,0.25,2))) throw new Error("invalid canvas viewport")
  if (payload.layout_revision !== undefined && (typeof payload.layout_revision!=="string" || !/^(0|[1-9][0-9]*)$/.test(payload.layout_revision)))
    throw new Error("invalid layout revision")
}

const between = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high
