import assert from "node:assert/strict"
import { test } from "node:test"
import { validateCanvas } from "./canvas-model.ts"

const valid = () => ({
  label: "Connected Things",
  nodes: [
    { id: "thermostat", kind: "thing", title: "Thermostat", identity: "urn:test:thermostat", value: "21.5", unit: "°C", status: "Read", detail: "Explicit read", x: 0, y: 100 },
    { id: "process", kind: "process", title: "Smart room", identity: "smart_room", value: "", unit: "", status: "Idle", detail: "", x: 300, y: 100 },
  ],
  edges: [{ id: "temperature", source: "thermostat", target: "process", kind: "input", label: "temperature · °C", target_handle: "temperature" }],
})

test("admitted Thing graphs include baseline unit text and typed connections", () => {
  assert.doesNotThrow(() => validateCanvas(valid()))
  assert.doesNotThrow(() => validateCanvas({ label: "Empty", nodes: [], edges: [] }))
})

test("rejects malformed graph identities, payloads and coordinates before mounting", () => {
  const changes: Array<(payload: ReturnType<typeof valid>) => void> = [
    (p) => { p.nodes.push(p.nodes[0]) },
    (p) => { p.nodes[0].x = Infinity },
    (p) => { p.nodes[0].x = 20001 },
    (p) => { p.nodes[0].title = "字".repeat(43) },
    (p) => { p.nodes[0].kind = "command" },
    (p) => { p.nodes[0] = { ...p.nodes[0], ...{ private: "hidden" } } },
    (p) => { p.edges[0].target = "other-session" },
    (p) => { p.edges[0].target_handle = "action" },
    (p) => { p.edges.push(p.edges[0]) },
    (p) => { p.nodes = Array.from({ length: 33 }, () => p.nodes[0]) },
    (p) => { p.edges = Array.from({ length: 65 }, () => p.edges[0]) },
  ]
  for (const change of changes) {
    const payload = valid()
    change(payload)
    assert.throws(() => validateCanvas(payload))
  }
})
