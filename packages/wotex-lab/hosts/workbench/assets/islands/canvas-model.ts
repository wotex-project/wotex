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
  operations?: ("read" | "observe" | "pause")[]
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

export interface MetricSeries {
  name: string
  points: [number, number | null][]
}

export interface CanvasMetricPin extends Record<string, unknown> {
  id: string
  title: string
  metric: string
  source: string
  range: string
  unit: string
  aggregation: string
  state: string
  auto_refresh: boolean
  end_ms: number
  series: MetricSeries[]
  x: number
  y: number
  width: number
  height: number
}

export interface RunOutcome {
  label: string
  value: string
  unit: string
  note: string
}

export interface CanvasRunPin extends Record<string, unknown> {
  kind: "run"
  id: string
  title: string
  run_id: string
  record_digest: string
  chart_index: number
  source_mode: string
  state: string
  started_at: string
  unit: string
  mark: "line" | "point" | "area"
  outcome: RunOutcome | null
  series: MetricSeries[]
  x: number
  y: number
  width: number
  height: number
}

export type CanvasPin = CanvasMetricPin | CanvasRunPin
export interface CanvasViewport {
  x: number
  y: number
  zoom: number
}

const nodeFields = [
  "id",
  "kind",
  "title",
  "identity",
  "value",
  "unit",
  "status",
  "detail",
  "x",
  "y",
]

const edgeFields = ["id", "source", "target", "label", "kind", "target_handle"]
const textLimits = {
  id: 128,
  title: 128,
  identity: 256,
  value: 128,
  unit: 32,
  status: 32,
  detail: 128,
}

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
  if (!Array.isArray(nodes) || nodes.length > 32 || !Array.isArray(edges) || edges.length > 64) {
    throw new Error("invalid canvas limits")
  }
  const ids = new Set<string>()
  for (const node of nodes) {
    if (
      !record(node) ||
      !exact(
        Object.fromEntries(Object.entries(node).filter(([key]) => key !== "operations")),
        nodeFields,
      ) ||
      !identifier(node.id) ||
      ids.has(node.id) ||
      (node.operations !== undefined &&
        (!Array.isArray(node.operations) ||
          node.operations.length > 3 ||
          new Set(node.operations).size !== node.operations.length ||
          !node.operations.every(
            (op) => typeof op === "string" && ["read", "observe", "pause"].includes(op),
          ))) ||
      !["thing", "process", "entry"].includes(String(node.kind)) ||
      !Object.entries(textLimits).every(([key, limit]) => text(node[key], limit)) ||
      !coordinate(node.x) ||
      !coordinate(node.y)
    ) {
      throw new Error("invalid canvas node")
    }
    ids.add(node.id)
  }
  const edgeIds = new Set<string>()
  for (const edge of edges) {
    if (
      !record(edge) ||
      !exact(edge, edgeFields) ||
      !identifier(edge.id) ||
      edgeIds.has(edge.id) ||
      !identifier(edge.source) ||
      !identifier(edge.target) ||
      !ids.has(edge.source) ||
      !ids.has(edge.target) ||
      !text(edge.label, 128) ||
      !["input", "proposal"].includes(String(edge.kind)) ||
      !["temperature", "power", "input"].includes(String(edge.target_handle))
    ) {
      throw new Error("invalid canvas edge")
    }
    edgeIds.add(edge.id)
  }
  validatePins(payload.pins ?? [], ids)
  if (
    payload.selection !== undefined &&
    payload.selection !== "" &&
    (typeof payload.selection !== "string" || !ids.has(payload.selection))
  ) {
    throw new Error("invalid canvas selection")
  }
  validateViewport(payload)
}

function validatePins(pins: JsonValue, ids: Set<string>): void {
  if (!Array.isArray(pins) || pins.length > 16) {
    throw new Error("invalid canvas pins")
  }
  for (const pin of pins) {
    if (!record(pin)) {
      throw new Error("invalid canvas pin")
    }
    const run = pin.kind === "run"
    const fields = run
      ? [
          "kind",
          "id",
          "title",
          "run_id",
          "record_digest",
          "chart_index",
          "source_mode",
          "state",
          "started_at",
          "unit",
          "mark",
          "outcome",
          "series",
          "x",
          "y",
          "width",
          "height",
        ]
      : [
          "id",
          "title",
          "metric",
          "source",
          "range",
          "unit",
          "aggregation",
          "state",
          "auto_refresh",
          "end_ms",
          "series",
          "x",
          "y",
          "width",
          "height",
        ]
    if (
      !exact(pin, fields) ||
      !identifier(pin.id) ||
      ids.has(pin.id) ||
      !text(pin.title, 128) ||
      !text(pin.unit, 32) ||
      !text(pin.state, 64) ||
      !(run ? runIdentity(pin) : metricIdentity(pin)) ||
      !coordinate(pin.x) ||
      !coordinate(pin.y) ||
      !between(pin.width, 300, 800) ||
      !between(pin.height, 200, 600) ||
      !Array.isArray(pin.series) ||
      pin.series.length > 8
    ) {
      throw new Error("invalid canvas pin")
    }
    const pointCount = validatePinSeries(pin.series, run)
    if (run && pointCount > 512) {
      throw new Error("invalid run pin points")
    }
    ids.add(pin.id)
  }
}

function validatePinSeries(entries: unknown[], run: boolean): number {
  const names = new Set<string>()
  let pointCount = 0
  for (const series of entries) {
    if (
      !record(series) ||
      !exact(series, ["name", "points"]) ||
      !text(series.name, 128) ||
      names.has(series.name) ||
      !Array.isArray(series.points) ||
      series.points.length > (run ? 512 : 61) ||
      !series.points.every(
        (p) =>
          Array.isArray(p) &&
          p.length === 2 &&
          between(p[0], -1e100, 1e100) &&
          (p[1] === null || between(p[1], -1e100, 1e100)),
      )
    ) {
      throw new Error("invalid pin series")
    }
    pointCount += series.points.length
    names.add(series.name)
  }
  return pointCount
}

function validateViewport(payload: Record<string, JsonValue>): void {
  const view = payload.view ?? []
  if (
    !Array.isArray(view) ||
    view.length > 1 ||
    !view.every(
      (v) =>
        record(v) &&
        exact(v, ["x", "y", "zoom"]) &&
        between(v.x, -100000, 100000) &&
        between(v.y, -100000, 100000) &&
        between(v.zoom, 0.25, 2),
    )
  ) {
    throw new Error("invalid canvas viewport")
  }
  if (
    payload.layout_revision !== undefined &&
    (typeof payload.layout_revision !== "string" ||
      !/^(0|[1-9][0-9]*)$/.test(payload.layout_revision))
  ) {
    throw new Error("invalid layout revision")
  }
}

function metricIdentity(pin: Record<string, unknown>): boolean {
  return (
    identifier(pin.metric) &&
    text(pin.source, 64) &&
    text(pin.aggregation, 64) &&
    ["5m", "15m", "1h"].includes(String(pin.range)) &&
    typeof pin.auto_refresh === "boolean" &&
    Number.isSafeInteger(pin.end_ms)
  )
}

function runIdentity(pin: Record<string, unknown>): boolean {
  const o = pin.outcome
  return (
    identifier(pin.run_id) &&
    text(pin.record_digest, 71) &&
    /^sha256:[0-9a-f]{64}$/.test(pin.record_digest) &&
    Number.isInteger(pin.chart_index) &&
    between(pin.chart_index, 0, 7) &&
    text(pin.source_mode, 64) &&
    ["line", "point", "area"].includes(String(pin.mark)) &&
    text(pin.started_at, 32) &&
    utcTimestamp(pin.started_at) &&
    (o === null ||
      (record(o) &&
        exact(o, ["label", "value", "unit", "note"]) &&
        text(o.label, 128) &&
        text(o.value, 128) &&
        text(o.unit, 32) &&
        text(o.note, 128)))
  )
}

function utcTimestamp(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$/.exec(value)
  if (!match) {
    return false
  }
  const d = new Date(value)
  return (
    Number.isFinite(d.getTime()) &&
    [
      d.getUTCFullYear(),
      d.getUTCMonth() + 1,
      d.getUTCDate(),
      d.getUTCHours(),
      d.getUTCMinutes(),
      d.getUTCSeconds(),
    ].every((v, i) => v === Number(match[i + 1]))
  )
}

const between = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high
