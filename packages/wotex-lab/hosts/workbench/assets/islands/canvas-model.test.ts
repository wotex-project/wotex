import assert from "node:assert/strict"
import { test } from "node:test"
import { validateCanvas } from "./canvas-model.ts"
import type {JsonValue} from "./types.js"
import type { FullSnapshot } from "./types.js"
import { createServer } from "vite"

const valid = () => ({
  label: "Connected Things",
  nodes: [
    { id: "thermostat", kind: "thing", title: "Thermostat", identity: "urn:test:thermostat", value: "21.5", unit: "°C", status: "Read", detail: "Explicit read", x: 0, y: 100 },
    { id: "process", kind: "process", title: "Smart room", identity: "smart_room", value: "", unit: "", status: "Idle", detail: "", x: 300, y: 100 },
  ],
  edges: [{ id: "temperature", source: "thermostat", target: "process", kind: "input", label: "temperature · °C", target_handle: "temperature" }],
})

test("the real client event builder admits Property controls and rejects extra authority", async () => {
  const server = await createServer({configFile:false,server:{middlewareMode:true,watch:null}})
  try {
    const {buildEvent} = await server.ssrLoadModule(new URL("./protocol.ts",import.meta.url).pathname)
    const snapshot: FullSnapshot = {schema:"wotex-lab-island/v1",component:"canvas",instance_id:"room--canvas",generation:"1",revision:"7",payload_digest:"sha256:"+"a".repeat(64),capabilities:["read","observe","pause","statistics","sources","inspect_connection"],payload:valid()}
    for(const event of ["read","observe","pause","statistics","sources","inspect_connection"]) {
      assert.deepEqual(buildEvent(snapshot,event,{id:"thermostat"}),{
        schema:"wotex-lab-island-event/v1",component:"canvas",instance_id:"room--canvas",client_revision:"7",event,payload:{id:"thermostat"},
      })
      assert.throws(()=>buildEvent(snapshot,event,{id:"thermostat",operation:"invokeaction"}))
    }
    const connection = {source:"thing-actuator",target:"process-smart-room",target_handle:"temperature"}
    assert.deepEqual(buildEvent(snapshot,"propose_connection",{connection}).payload,{connection})
    assert.throws(()=>buildEvent(snapshot,"propose_connection",{id:"temperature"}))
    assert.throws(()=>buildEvent(snapshot,"propose_connection",{connection,authority:"grant"}))
    assert.throws(()=>buildEvent(snapshot,"apply_connection",{connection}))
    assert.throws(()=>buildEvent(snapshot,"dispatch",{id:"thermostat"}))
  } finally { await server.close() }
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

test("node operations admit only distinct closed capabilities and keep legacy nodes valid", () => {
  for(const operations of [[],["read","observe"],["read","pause"]]) {
    const payload = valid()
    Object.assign(payload.nodes[0],{operations})
    assert.doesNotThrow(()=>validateCanvas(payload))
  }
  for(const operations of ["read",["read","read"],["dispatch"],[["read"]],[{},"observe"]]) {
    const payload = valid()
    Object.assign(payload.nodes[0],{operations})
    assert.throws(()=>validateCanvas(payload))
  }
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
