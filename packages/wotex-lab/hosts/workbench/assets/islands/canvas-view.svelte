<script lang="ts">
import { SvelteFlow, MarkerType, useSvelteFlow, type Node, type Edge } from "@xyflow/svelte"
import { tick, untrack } from "svelte"
import CanvasThing from "./canvas-node.svelte"
import CanvasMetric from "./canvas-metric.svelte"
import type { CanvasNode, CanvasEdge, CanvasPin, CanvasViewport } from "./canvas-model.js"
import type { IslandTransport, JsonValue } from "./types.js"
import pointer from "./canvas-assets/mouse-pointer-2.svg"
import hand from "./canvas-assets/hand.svg"
import fit from "./canvas-assets/maximize.svg"
import plus from "./canvas-assets/plus.svg"
import metrics from "./canvas-assets/chart-no-axes-combined.svg"
import experiments from "./canvas-assets/flask-conical.svg"
import save from "./canvas-assets/save.svg"

let { payload, transport, connected }: { payload: Record<string, JsonValue>; transport: IslandTransport; connected: boolean } = $props()
const flow = useSvelteFlow()
const nodeTypes = { thing: CanvasThing, metric: CanvasMetric }
let root: HTMLDivElement
let firstAction = $state<HTMLButtonElement>()
let nodes = $state.raw<Node[]>([])
let edges = $state.raw<Edge[]>([])
let pan = $state(false)
let menu = $state<{ id: string; x: number; y: number } | null>(null)
let error = $state("")
const initialViewport = () => (payload.view as unknown as CanvasViewport[] | undefined)?.[0]
const savedViewport = initialViewport()
let viewport = $state(savedViewport ?? { x: 0, y: 0, zoom: 1 })
let width = $state(0)
let height = $state(0)
let layoutRevision = ""
let saving = $state(false)
let saved = $state(false)
const menuNode = $derived(nodes.find(n=>n.id===menu?.id))
const pinMenu = $derived(menuNode?.type==="metric")

async function open(id: string, event: MouseEvent) {
  event.preventDefault()
  event.stopPropagation()
  const bounds = root.getBoundingClientRect()
  menu = { id, x: Math.max(8, Math.min(event.clientX - bounds.left, bounds.width - 208)), y: Math.max(8, Math.min(event.clientY - bounds.top, bounds.height - 184)) }
  nodes = nodes.map((node) => ({ ...node, selected: node.id === id }))
  await tick()
  firstAction?.focus()
}

$effect(() => {
  const incoming = payload.nodes as unknown as CanvasNode[]
  const connections = payload.edges as unknown as CanvasEdge[]
  const pins = (payload.pins ?? []) as unknown as CanvasPin[]
  const revision = String(payload.layout_revision ?? "0")
  const restore = layoutRevision !== "" && layoutRevision !== revision
  const previous = new Map(untrack(() => nodes).map((node) => [node.id, node]))
  nodes = [...incoming.map((node) => ({
    ...previous.get(node.id),
    id: node.id, type: "thing", position: restore ? {x:node.x,y:node.y} : previous.get(node.id)?.position ?? { x: node.x, y: node.y },
    selected: previous.get(node.id)?.selected ?? false,
    ariaLabel: `${node.title}, ${node.value} ${node.unit}, ${node.status}`,
    data: { ...node, open },
  })), ...pins.map(pin=>({
    ...previous.get(pin.id), id:pin.id,type:"metric",
    position:restore?{x:pin.x,y:pin.y}:previous.get(pin.id)?.position ?? {x:pin.x,y:pin.y},
    width:restore?pin.width:previous.get(pin.id)?.width ?? pin.width,
    height:restore?pin.height:previous.get(pin.id)?.height ?? pin.height,
    ariaLabel:`${pin.title}, ${pin.source}, ${pin.state}`,
    data:{...pin,open,changed:()=>{saved=false}},
  }))]
  if(restore && Array.isArray(payload.view) && payload.view[0]) viewport=payload.view[0] as unknown as CanvasViewport
  layoutRevision=revision
  if(previous.size && pins.some(pin=>!previous.has(pin.id))) {
    void tick().then(()=>flow.fitView({padding:0.2,maxZoom:1}))
  }
  edges = connections.map((edge) => ({
    id: edge.id, source: edge.source, target: edge.target, label: edge.label,
    sourceHandle: "output", targetHandle: edge.target_handle, type: "smoothstep",
    class: edge.kind === "proposal" ? "wl-canvas-proposal" : "wl-canvas-input",
    markerEnd: { type: MarkerType.ArrowClosed, color: "var(--wl-canvas-muted)" },
  }))
})

async function inspect() {
  if (!connected || !menu) return
  const id = menu.id
  menu = null
  await send("inspect", id)
}

async function send(event: "inspect" | "open" | "pin_refresh" | "pin_pause" | "pin_resume" | "pin_remove", id: string) {
  if (!connected) return
  if (event === "open") menu = null
  error = ""
  try {
    const reply = await transport.push(event, { id })
    if (!reply || Array.isArray(reply) || typeof reply !== "object" || reply.status !== "accepted")
      error = "Selection changed. Open the Thing again."
  } catch { error = "Reconnect to continue." }
}

async function saveLayout(){
  if(!connected||saving)return
  saving=true;error="";saved=false
  try {
    const positions=nodes.map(n=>({id:n.id,...n.position,...(n.type==="metric"?{width:n.width??360,height:n.height??280}:{})}))
    const reply=await transport.push("save_layout",{layout:{positions,viewport:{x:viewport.x,y:viewport.y,zoom:viewport.zoom}}})
    if(reply && !Array.isArray(reply) && typeof reply==="object" && reply.status==="accepted") saved=true
    else error="Layout was not saved. Reconnect and try again."
  } catch { error="Reconnect to save this layout." }
  finally { saving=false }
}

function closeMenu() {
  const id = menu?.id
  menu = null
  if (id) root.querySelector<HTMLElement>(`[data-id="${id}"]`)?.focus()
}
</script>

<div bind:this={root} bind:clientWidth={width} bind:clientHeight={height} class="wl-connected-canvas" data-wotex-connected={connected}
  style:background-size={`${104 * viewport.zoom}px ${104 * viewport.zoom}px`}
  style:background-position={`${viewport.x}px ${viewport.y}px`}>
  {#if width > 0 && height > 0}
  <SvelteFlow bind:nodes bind:edges bind:viewport {nodeTypes} {width} {height} nodesConnectable={false}
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
    <button type="button" aria-label="Metrics" title="Metrics" disabled={!connected} onclick={() => { void send("open", "metrics") }}><img src={metrics} alt="" /></button>
    <button type="button" aria-label="Experiments" title="Experiments" disabled={!connected} onclick={() => { void send("open", "experiments") }}><img src={experiments} alt="" /></button>
    <button type="button" aria-label="Save layout" title={saved?"Layout saved":"Save layout"} disabled={!connected||saving} onclick={()=>{void saveLayout()}}><img src={save} alt="" /></button>
    <button type="button" aria-label="Fit connected Things" onclick={() => { void flow.fitView({ padding: 0.2, maxZoom: 1 }) }}><img src={fit} alt="" /></button>
  </nav>
  {#if menu}
    <div class="wl-canvas-context" role="menu" tabindex="-1" aria-label="Thing actions" style:left={`${menu.x}px`} style:top={`${menu.y}px`}
      onkeydown={(event) => {
        if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); closeMenu(); return }
        if (event.key === "Tab") { menu = null; return }
        if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
          event.preventDefault()
          const items = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)")]
          const index = items.indexOf(document.activeElement as HTMLButtonElement)
          const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : (index + (event.key === "ArrowUp" ? -1 : 1) + items.length) % items.length
          items[next]?.focus()
        }
      }}>
      <button bind:this={firstAction} type="button" role="menuitem" disabled={!connected} onclick={() => { void inspect() }}>{pinMenu ? "Rename / sources" : menu.id === "process-smart-room" ? "Configure" : "Inspect"}</button>
      {#if pinMenu}
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send("pin_refresh",menu.id);menu=null}}>Refresh</button>
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send(menuNode?.data.auto_refresh?"pin_pause":"pin_resume",menu.id);menu=null}}>{menuNode?.data.auto_refresh?"Pause":"Resume"}</button>
        <button type="button" role="menuitem" disabled={!connected} onclick={()=>{if(menu)void send("pin_remove",menu.id);menu=null}}>Remove</button>
      {:else}<button type="button" role="menuitem" disabled={!connected} onclick={() => { void send("open", "metrics") }}>Room metrics</button>{/if}
    </div>
  {/if}
  {#if !connected}<span class="wl-canvas-notice" role="status">Disconnected</span>{/if}
  {#if error}<span class="wl-canvas-notice" role="alert">{error}</span>{/if}
</div>
