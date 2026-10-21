<script lang="ts">
import { SvelteFlow, MarkerType, useSvelteFlow, type Node, type Edge } from "@xyflow/svelte"
import { tick, untrack } from "svelte"
import CanvasThing from "./canvas-node.svelte"
import type { CanvasNode, CanvasEdge } from "./canvas-model.js"
import type { IslandTransport, JsonValue } from "./types.js"
import pointer from "./canvas-assets/mouse-pointer-2.svg"
import hand from "./canvas-assets/hand.svg"
import fit from "./canvas-assets/maximize.svg"
import plus from "./canvas-assets/plus.svg"
import metrics from "./canvas-assets/chart-no-axes-combined.svg"
import experiments from "./canvas-assets/flask-conical.svg"

let { payload, transport, connected }: { payload: Record<string, JsonValue>; transport: IslandTransport; connected: boolean } = $props()
const flow = useSvelteFlow()
const nodeTypes = { thing: CanvasThing }
let root: HTMLDivElement
let firstAction = $state<HTMLButtonElement>()
let nodes = $state.raw<Node[]>([])
let edges = $state.raw<Edge[]>([])
let pan = $state(false)
let menu = $state<{ id: string; x: number; y: number } | null>(null)
let error = $state("")
let viewport = $state({ x: 0, y: 0, zoom: 1 })
let width = $state(0)
let height = $state(0)

async function open(id: string, event: MouseEvent) {
  event.preventDefault()
  event.stopPropagation()
  const bounds = root.getBoundingClientRect()
  menu = { id, x: Math.max(8, Math.min(event.clientX - bounds.left, bounds.width - 168)), y: Math.max(8, Math.min(event.clientY - bounds.top, bounds.height - 72)) }
  nodes = nodes.map((node) => ({ ...node, selected: node.id === id }))
  await tick()
  firstAction?.focus()
}

$effect(() => {
  const incoming = payload.nodes as unknown as CanvasNode[]
  const connections = payload.edges as unknown as CanvasEdge[]
  const previous = new Map(untrack(() => nodes).map((node) => [node.id, node]))
  nodes = incoming.map((node) => ({
    ...previous.get(node.id),
    id: node.id, type: "thing", position: previous.get(node.id)?.position ?? { x: node.x, y: node.y },
    selected: previous.get(node.id)?.selected ?? false,
    ariaLabel: `${node.title}, ${node.value} ${node.unit}, ${node.status}`,
    data: { ...node, open },
  }))
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

async function send(event: "inspect" | "open", id: string) {
  if (!connected) return
  if (event === "open") menu = null
  error = ""
  try {
    const reply = await transport.push(event, { id })
    if (!reply || Array.isArray(reply) || typeof reply !== "object" || reply.status !== "accepted")
      error = "Selection changed. Open the Thing again."
  } catch { error = "Reconnect to continue." }
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
    deleteKey={null} minZoom={0.25} maxZoom={2} fitView fitViewOptions={{ padding: 0.2, maxZoom: 1 }}
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
      <button bind:this={firstAction} type="button" role="menuitem" disabled={!connected} onclick={() => { void inspect() }}>{menu.id === "process-smart-room" ? "Configure" : "Inspect"}</button>
      <button type="button" role="menuitem" disabled={!connected} onclick={() => { void send("open", "metrics") }}>Room metrics</button>
    </div>
  {/if}
  {#if !connected}<span class="wl-canvas-notice" role="status">Disconnected</span>{/if}
  {#if error}<span class="wl-canvas-notice" role="alert">{error}</span>{/if}
</div>
