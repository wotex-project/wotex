import assert from "node:assert/strict"
import { test } from "node:test"
import { validateCanvas } from "./canvas-model.ts"
import type {JsonValue} from "./types.js"

const valid = () => ({
  label: "Connected Things",
  nodes: [
    { id: "thermostat", kind: "thing", title: "Thermostat", identity: "urn:test:thermostat", value: "21.5", unit: "°C", status: "Read", detail: "Explicit read", x: 0, y: 100 },
    { id: "process", kind: "process", title: "Smart room", identity: "smart_room", value: "", unit: "", status: "Idle", detail: "", x: 300, y: 100 },
  ],
  edges: [{ id: "temperature", source: "thermostat", target: "process", kind: "input", label: "temperature · °C", target_handle: "temperature" }],
})

test("metric pins retain missing and negative data while refusing forged geometry or identities", () => {
  const payload = ():Record<string,JsonValue> => ({...valid(), pins:[{
    id:"pin-nx",title:"Rows",metric:"nx_batch_rows",source:"Room history",range:"5m",unit:"rows",
    aggregation:"last value per step",state:"Paused",auto_refresh:false,end_ms:1799000300000,
    series:[{name:"room",points:[[-20,-4],[-15,null],[-10,2]]}],x:100,y:200,width:360,height:280,
  }],view:[{x:-100,y:50,zoom:0.75}],layout_revision:"1"})
  assert.doesNotThrow(()=>validateCanvas(payload()))
  for(const [field,value] of [["id","thermostat"],["auto_refresh","true"],["width",299],["height",601],
    ["x",Infinity],["series",[{name:"room",points:[[0,"missing"]]}]]] as [string,JsonValue][]) {
    const p=payload();(p.pins as Record<string,JsonValue>[])[0][field]=value
    assert.throws(()=>validateCanvas(p))
  }
})

test("admitted Thing graphs include baseline unit text and typed connections", () => {
  assert.doesNotThrow(() => validateCanvas(valid()))
  assert.doesNotThrow(() => validateCanvas({...valid(),selection:"thermostat"}))
  assert.throws(() => validateCanvas({...valid(),selection:"other-session"}))
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
