<script lang="ts">
import { SvelteFlowProvider } from "@xyflow/svelte"
import "@xyflow/svelte/dist/style.css"
import CanvasView from "./canvas-view.svelte"
import type { IslandTransport, JsonValue } from "./types.js"
import "./canvas.css"

let { payload, transport }: { payload: Record<string, JsonValue>; transport: IslandTransport } = $props()
const initial = () => ({ payload: { ...payload }, connected: transport.connected() })
const initialState = initial()
let current = $state(initialState.payload)
let connected = $state(initialState.connected)
export function update(next: Record<string, JsonValue>) { current = next }
export function setConnected(next: boolean) { connected = next }
</script>

<SvelteFlowProvider>
  <CanvasView payload={current} {transport} {connected} />
</SvelteFlowProvider>
