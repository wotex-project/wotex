<script lang="ts">
import { SvelteFlow, MarkerType, useSvelteFlow, type Node, type Edge, type Connection } from "@xyflow/svelte"
import { onMount, tick, untrack } from "svelte"
import CanvasThing from "./canvas-node.svelte"
import CanvasMetric from "./canvas-metric.svelte"
import CanvasRun from "./canvas-run.svelte"
import type { CanvasNode, CanvasEdge, CanvasPin, CanvasViewport } from "./canvas-model.js"
import type { IslandTransport, JsonValue } from "./types.js"
import pointer from "./canvas-assets/mouse-pointer-2.svg"
import hand from "./canvas-assets/hand.svg"
import fit from "./canvas-assets/maximize.svg"
import plus from "./canvas-assets/plus.svg"
import metrics from "./canvas-assets/chart-no-axes-combined.svg"
import experiments from "./canvas-assets/flask-conical.svg"
import save from "./canvas-assets/save.svg"
import connectionsIcon from "./canvas-assets/waypoints.svg"

let { payload, transport, connected }: { payload: Record<string, JsonValue>; transport: IslandTransport; connected: boolean } = $props()
const flow = useSvelteFlow()
const nodeTypes = { thing: CanvasThing, metric: CanvasMetric, run_result: CanvasRun }
let root: HTMLDivElement
let firstAction = $state<HTMLButtonElement>()
let nodes = $state.raw<Node[]>([])
let edges = $state.raw<Edge[]>([])
let pan = $state(false)
let menu = $state<{ kind: "node" | "edge"; id: string; x: number; y: number } | null>(null)
let error = $state("")
const initialViewport = () => (payload.view as unknown as CanvasViewport[] | undefined)?.[0]
const savedViewport = initialViewport()
let viewport = $state(savedViewport ?? { x: 0, y: 0, zoom: 1 })
let width = $state(0)
let height = $state(0)
let layoutRevision = ""
let saving = $state(false)
let openingDocumentation = false
let lastSelection = ""
let saved = $state(false)
let focusOrigin: { element: HTMLElement | SVGElement; id: string | null; edge: boolean; label: string | null } | null = null
const menuNode = $derived(nodes.find(n=>n.id===menu?.id))
const pinMenu = $derived(menuNode?.type==="metric")
const runPinMenu = $derived(menuNode?.type==="run_result")
const menuOperations = $derived(menuNode?.type==="thing" ? (menuNode.data as CanvasNode).operations ?? [] : [])

async function openMenu(kind: "node" | "edge", id: string, event: MouseEvent | KeyboardEvent) {
  event.preventDefault()
  event.stopPropagation()
  const bounds = root.getBoundingClientRect()
  rememberFocus(event.target)
  const anchor = event.target instanceof Element ? event.target.closest("button,[data-id]") ?? event.target : root
  const target = anchor.getBoundingClientRect()
  const x = "clientX" in event && event.clientX ? event.clientX : target.x + target.width / 2
  const y = "clientY" in event && event.clientY ? event.clientY : target.y + target.height / 2
  menu = { kind, id, x: Math.max(8, Math.min(x - bounds.left, bounds.width - 208)), y: Math.max(8, Math.min(y - bounds.top, bounds.height - 244)) }
  if(kind === "node") {
    nodes = nodes.map((node) => ({ ...node, selected: node.id === id }))
    edges = edges.map(edge=>({...edge,selected:false}))
  } else selectEdge(id)
  await tick()
  firstAction?.focus()
}

const open = (id: string, event: MouseEvent) => openMenu("node", id, event)

function validConnection(connection: Connection | Edge) {
  if(!connected) return false
  const source = nodes.find(node=>node.id===connection.source)
  const target = nodes.find(node=>node.id===connection.target)
  return Boolean(source && target && (
    (source.data.kind === "thing" && target.data.kind === "process" && ["temperature","power"].includes(connection.targetHandle ?? "")) ||
    (source.data.kind === "process" && target.id === "thing-actuator" && connection.targetHandle === "input")
  ))
}

function proposeConnection(connection: Connection): false {
  if(!connected) return false
  menu=null;error=""
  void transport.push("propose_connection",{connection:{source:connection.source,target:connection.target,target_handle:connection.targetHandle ?? ""}})
    .then(reply=>{
      if(!reply || Array.isArray(reply) || typeof reply!=="object" || reply.status!=="accepted")
        error="No compatible connection for these endpoints."
    })
    .catch(()=>{error="Reconnect to configure connections."})
  // The server adds an applied edge; Svelte Flow must not add this draft.
  return false
}

$effect(() => {
  const incoming = payload.nodes as unknown as CanvasNode[]
  const connections = payload.edges as unknown as CanvasEdge[]
  const pins = (payload.pins ?? []) as unknown as CanvasPin[]
  const revision = String(payload.layout_revision ?? "0")
  const restore = layoutRevision !== "" && layoutRevision !== revision
  const selection = String(payload.selection ?? "")
  const select = selection !== "" && lastSelection !== selection
  lastSelection = selection
  const previous = new Map(untrack(() => nodes).map((node) => [node.id, node]))
  nodes = [...incoming.map((node) => ({
    ...previous.get(node.id),
    id: node.id, type: "thing", position: restore ? {x:node.x,y:node.y} : previous.get(node.id)?.position ?? { x: node.x, y: node.y },
    selected: select ? node.id===selection : previous.get(node.id)?.selected ?? node.id===selection,
    ariaLabel: [node.title,`${node.value} ${node.unit}`.trim(),node.status].filter(Boolean).join(", "),
    data: { ...node, open, connectable: connected && node.kind !== "entry" },
  })), ...pins.map(pin=>({
    ...previous.get(pin.id), id:pin.id,type:pin.kind==="run"?"run_result":"metric",
    position:restore?{x:pin.x,y:pin.y}:previous.get(pin.id)?.position ?? {x:pin.x,y:pin.y},
    selected:select?pin.id===selection:previous.get(pin.id)?.selected ?? pin.id===selection,
    width:restore?pin.width:previous.get(pin.id)?.width ?? pin.width,
    height:restore?pin.height:previous.get(pin.id)?.height ?? pin.height,
    ariaLabel:`${pin.title}, ${pin.kind==="run"?pin.run_id:pin.source}, ${pin.state}`,
    data:{...pin,open,changed:()=>{saved=false}},
  }))]
  if(restore && Array.isArray(payload.view) && payload.view[0]) viewport=payload.view[0] as unknown as CanvasViewport
  layoutRevision=revision
  if(previous.size && pins.some(pin=>!previous.has(pin.id))) {
    void tick().then(()=>flow.fitView({padding:0.2,maxZoom:1}))
  }
  const previousEdges = new Map(untrack(()=>edges).map(edge=>[edge.id,edge]))
  edges = connections.map((edge) => ({
    ...previousEdges.get(edge.id),
    id: edge.id, source: edge.source, target: edge.target, label: edge.label,
    sourceHandle: "output", targetHandle: edge.target_handle, type: "smoothstep",
    class: edge.kind === "proposal" ? "wl-canvas-proposal" : "wl-canvas-input",
    markerEnd: { type: MarkerType.ArrowClosed, color: "var(--wl-canvas-muted)" },
    focusable: true, ariaRole: "button", ariaLabel: `Configure ${edge.label} connection`,
    domAttributes: {onkeydown:(event: KeyboardEvent)=>{
      if(["Enter"," "].includes(event.key)) {event.preventDefault();event.stopPropagation();void send("inspect_connection",edge.id)}
      else if(event.key==="ContextMenu" || (event.key==="F10" && event.shiftKey)) {void openMenu("edge",edge.id,event)}
    }},
  }))
})

async function inspect() {
  if (!connected || !menu) return
  const { id, kind } = menu
  menu = null
  await send(kind === "edge" ? "inspect_connection" : "inspect", id)
}

async function send(event: "inspect" | "inspect_connection" | "open" | "read" | "observe" | "pause" | "statistics" | "sources" | "pin_refresh" | "pin_pause" | "pin_resume" | "pin_remove" | "pin_open_run", id: string) {
  if (!connected) return
  if(event === "inspect_connection") selectEdge(id)
  menu = null
  error = ""
  try {
    const reply = await transport.push(event, { id })
    if (reply && !Array.isArray(reply) && typeof reply === "object" &&
        (reply.status === "accepted" || (reply.status === "rejected" && reply.feedback === "host"))) return
    error = "Selection changed. Reopen it."
  } catch { error = "Reconnect to continue." }
}

function currentLayout() {
  return {
    positions:nodes.map(n=>({id:n.id,...n.position,...(["metric","run_result"].includes(n.type??"")?{width:n.width??360,height:n.height??280}:{})})),
    viewport:{x:viewport.x,y:viewport.y,zoom:viewport.zoom},
  }
}

onMount(()=>{
  let restoreAfterPatch = false
  const requestFocusRestore = () => { restoreAfterPatch = true }
  const afterPatch = () => {
    if(!restoreAfterPatch) return
    restoreAfterPatch = false
    void tick().then(restoreFocus)
  }
  const recordFocus = (event: FocusEvent) => rememberFocus(event.target)
  const contextKey = (event: KeyboardEvent) => {
    if(menu || !(event.target instanceof Element) || !(event.key==="ContextMenu" || (event.key==="F10" && event.shiftKey))) return
    const node = event.target.closest<HTMLElement>(".svelte-flow__node")
    const id = node?.dataset.id
    if(id) void openMenu("node", id, event)
  }
  const openDocumentation = (event: Event) => {
    event.preventDefault()
    if(openingDocumentation)return
    if(!connected){error="Reconnect to open documentation without losing this view.";return}
    openingDocumentation=true
    error=""
    void transport.push("open_documentation",{view:{layout:currentLayout(),selection:nodes.find(n=>n.selected)?.id??""}})
      .then(reply=>{
        if(reply && !Array.isArray(reply) && typeof reply==="object" && reply.status==="accepted")
          transport.navigate("navigate","/docs/start/")
        else error="View changed. Open documentation again."
      })
      .catch(()=>{error="Reconnect to open documentation without losing this view."})
      .finally(()=>{openingDocumentation=false})
  }
  window.addEventListener("wotex:open-documentation",openDocumentation)
  window.addEventListener("wotex:restore-canvas-focus",requestFocusRestore)
  window.addEventListener("phx:page-loading-stop",afterPatch)
  root.addEventListener("focusin",recordFocus)
  root.addEventListener("keydown",contextKey)
  return ()=>{
    window.removeEventListener("wotex:open-documentation",openDocumentation)
    window.removeEventListener("wotex:restore-canvas-focus",requestFocusRestore)
    window.removeEventListener("phx:page-loading-stop",afterPatch)
    root.removeEventListener("focusin",recordFocus)
    root.removeEventListener("keydown",contextKey)
  }
})

async function saveLayout(){
  if(!connected||saving)return
  saving=true;error="";saved=false
  try {
    const reply=await transport.push("save_layout",{layout:currentLayout()})
    if(reply && !Array.isArray(reply) && typeof reply==="object" && reply.status==="accepted") saved=true
    else error="Layout was not saved. Reconnect and try again."
  } catch { error="Reconnect to save this layout." }
  finally { saving=false }
}

function closeMenu() {
  menu = null
  restoreFocus()
}

function selectEdge(id: string) {
  edges = edges.map(edge=>({...edge,selected:edge.id===id}))
  nodes = nodes.map(node=>({...node,selected:false}))
}

function rememberFocus(target: EventTarget | null) {
  if(!(target instanceof Element) || target.closest('[role="menu"]')) return
  const element = target.closest<HTMLElement | SVGElement>("button,[tabindex]")
  if(!element || !root.contains(element)) return
  const object = element.closest(".svelte-flow__node,.svelte-flow__edge")
  focusOrigin = {element,id:object?.getAttribute("data-id") ?? null,edge:Boolean(object?.matches(".svelte-flow__edge")),label:element.getAttribute("aria-label")}
}

function restoreFocus() {
  let target: HTMLElement | SVGElement | null = focusOrigin?.element ?? null
  if(target && !target.isConnected) {
    const object = focusOrigin?.id ? root.querySelector<HTMLElement | SVGElement>(`${focusOrigin.edge?".svelte-flow__edge":".svelte-flow__node"}[data-id="${CSS.escape(focusOrigin.id)}"]`) : null
    target = (focusOrigin?.label ? (object ?? root).querySelector<HTMLElement | SVGElement>(`[aria-label="${CSS.escape(focusOrigin.label)}"]`) : null) ?? object
  }
  if(!target || target.matches(":disabled") || !target.isConnected || !visibleInCanvas(target))
    target = focusOrigin ? root.querySelector<HTMLButtonElement>('.wl-canvas-tools [aria-label="Connections"]:not(:disabled)') : null
  const destination = target ?? document.getElementById("wl-board-toggle")
  destination?.focus({preventScroll:true})
}

function visibleInCanvas(target: Element) {
  const rect = target.getBoundingClientRect()
  const bounds = root.getBoundingClientRect()
  return (rect.width > 0 || rect.height > 0) && rect.right > bounds.left && rect.left < bounds.right && rect.bottom >= bounds.top && rect.top <= bounds.bottom
}
</script>

<div bind:this={root} bind:clientWidth={width} bind:clientHeight={height} class="wl-connected-canvas" data-wotex-connected={connected}
  style:background-size={`${104 * viewport.zoom}px ${104 * viewport.zoom}px`}
  style:background-position={`${viewport.x}px ${viewport.y}px`}>
  {#if width > 0 && height > 0}
  <SvelteFlow bind:nodes bind:edges bind:viewport {nodeTypes} {width} {height} nodesConnectable={connected}
    isValidConnection={validConnection} onbeforeconnect={proposeConnection}
    onedgeclick={({edge})=>{void send("inspect_connection",edge.id)}}
    onedgecontextmenu={({edge,event})=>{void openMenu("edge",edge.id,event)}}
    deleteKey={null} minZoom={0.25} maxZoom={2} fitView={!savedViewport} initialViewport={savedViewport} fitViewOptions={{ padding: 0.2, maxZoom: 1 }}
    nodeExtent={[[-20000,-20000],[20000,20000]]}
    onmove={()=>{saved=false}} onnodedrag={()=>{saved=false}}
    panOnDrag={pan ? true : [1, 2]} selectionOnDrag={!pan} attributionPosition="bottom-left"
    onnodecontextmenu={({ node, event }) => { void open(node.id, event) }}
    onpaneclick={() => { menu = null }}
  />
  {/if}
  <nav class="wl-canvas-tools" aria-label="Canvas tools">
    <button type="button" aria-label="Select" aria-pressed={!pan} onclick={() => { pan = false }}><img src={pointer} alt="" /></button>
    <button type="button" aria-label="Pan" aria-pressed={pan} onclick={() => { pan = true }}><img src={hand} alt="" /></button>
    <button type="button" aria-label="Add Thing" title="Add Thing" disabled={!connected} onclick={() => { void send("open", "add") }}><img src={plus} alt="" /></button>
    <button type="button" aria-label="Connections" title="Connections" disabled={!connected} onclick={() => { void send("open", "connections") }}><img src={connectionsIcon} alt="" /></button>
    <button type="button" aria-label="Metrics" title="Metrics" disabled={!connected} onclick={() => { void send("open", "metrics") }}><img src={metrics} alt="" /></button>
    <button type="button" aria-label="Experiments" title="Experiments" disabled={!connected} onclick={() => { void send("open", "experiments") }}><img src={experiments} alt="" /></button>
    <button type="button" aria-label="Save layout" title={saved?"Layout saved":"Save layout"} disabled={!connected||saving} onclick={()=>{void saveLayout()}}><img src={save} alt="" /></button>
    <button type="button" aria-label="Fit connected Things" onclick={() => { void flow.fitView({ padding: 0.2, maxZoom: 1 }) }}><img src={fit} alt="" /></button>
  </nav>
  {#if menu}
    <div class="wl-canvas-context" role="menu" tabindex="-1" aria-label={menu.kind === "edge" ? "Connection actions" : runPinMenu ? "Run result actions" : pinMenu ? "Metric actions" : "Thing actions"} style:left={`${menu.x}px`} style:top={`${menu.y}px`}
      onkeydown={(event) => {
        if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); closeMenu(); return }
        if (event.key === "Tab") { closeMenu(); return }
        if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
          event.preventDefault()
          const items = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)")]
          const index = items.indexOf(document.activeElement as HTMLButtonElement)
          const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : (index + (event.key === "ArrowUp" ? -1 : 1) + items.length) % items.length
          items[next]?.focus()
        }
      }}>
      <button bind:this={firstAction} type="button" role="menuitem" disabled={!connected} onclick={() => { void inspect() }}>{menu.kind === "edge" ? "Configure connection" : pinMenu || runPinMenu ? "Rename / sources" : menu.id === "process-smart-room" ? "Configure" : "Inspect"}</button>
      {#if runPinMenu}
        <button type="button" role="menuitem" disabled={!connected || menuNode?.data.outcome === null} onclick={()=>{if(menu)void send("pin_open_run",menu.id);menu=null}}>Open run</button>
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send("pin_remove",menu.id);menu=null}}>Remove</button>
      {:else if pinMenu}
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send("pin_refresh",menu.id);menu=null}}>Refresh</button>
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send(menuNode?.data.auto_refresh?"pin_pause":"pin_resume",menu.id);menu=null}}>{menuNode?.data.auto_refresh?"Pause":"Resume"}</button>
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send("pin_remove",menu.id);menu=null}}>Remove</button>
      {:else}
        {#if menu.kind === "node"}
        {#each menuOperations as operation}
          <button type="button" role="menuitem" disabled={!connected} onclick={() => { if(menu) void send(operation,menu.id) }}>{operation==="read"?"Read Property":operation==="observe"?"Observe updates":"Pause updates"}</button>
        {/each}
        {#if menuNode?.data.kind !== "process"}
          <button type="button" role="menuitem" disabled={!connected} onclick={() => { if(menu) void send("statistics", menu.id) }}>Statistics</button>
          <button type="button" role="menuitem" disabled={!connected} onclick={() => { if(menu) void send("sources", menu.id) }}>Sources</button>
        {/if}
        {/if}
        <button type="button" role="menuitem" disabled={!connected} onclick={() => { void send("open", "metrics") }}>Room metrics</button>
      {/if}
    </div>
  {/if}
  {#if !connected}<span class="wl-canvas-notice" role="status">Disconnected</span>{/if}
  {#if error}<span class="wl-canvas-notice" role="alert">{error}</span>{/if}
</div>
