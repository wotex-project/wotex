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
}
