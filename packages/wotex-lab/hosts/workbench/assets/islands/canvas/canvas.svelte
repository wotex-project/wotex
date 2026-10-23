<script lang="ts">
  import { SvelteFlowProvider } from "@xyflow/svelte"
  import "@xyflow/svelte/dist/style.css"
  import CanvasView from "$lib/components/canvas/canvas.svelte"
  import type { IslandTransport, JsonValue } from "$lib/islands/types.ts"
  import "$lib/components/canvas/canvas.css"

  let {
    payload,
    transport,
  }: {
    payload: Record<string, JsonValue>
    transport: IslandTransport
  } = $props()

  const initial = () => ({
    payload: {
      ...payload,
    },
    connected: transport.connected(),
  })

  const initialState = initial()
  let current = $state(initialState.payload)
  let connected = $state(initialState.connected)

  export const update = (next: Record<string, JsonValue>) => {
    current = next
  }

  export const setConnected = (next: boolean) => {
    connected = next
  }
</script>

<SvelteFlowProvider>
  <CanvasView payload={current} {transport} {connected} />
</SvelteFlowProvider>
