<script lang="ts">
  import { SvelteFlow, SvelteFlowProvider } from "@xyflow/svelte"
  import "@xyflow/svelte/dist/style.css"
  import "$lib/components/canvas/canvas.css"
  import CanvasMetric from "$lib/components/canvas-metric/canvas-metric.svelte"
  import CanvasThing from "$lib/components/canvas-node/canvas-node.svelte"
  import CanvasRun from "$lib/components/canvas-run/canvas-run.svelte"
  import type { JsonValue } from "$lib/islands/types.ts"

  let {
    payload,
    kind,
  }: { payload: Record<string, JsonValue>; kind: "thing" | "metric" | "run_result" } = $props()
  const nodeTypes = { thing: CanvasThing, metric: CanvasMetric, run_result: CanvasRun }

  const ignore = () => undefined

  const nodes = $derived([
    {
      id: String(payload.id),
      type: kind,
      position: { x: 0, y: 0 },
      width: 360,
      height: 280,
      data: { ...payload, open: ignore, changed: ignore, connectable: false },
    },
  ])
</script>

<SvelteFlowProvider>
  <div class="wl-connected-canvas" style="width: min(100%, 640px); height: 380px">
    <SvelteFlow {nodes} {nodeTypes} edges={[]} fitView fitViewOptions={{ maxZoom: 1 }} />
  </div>
</SvelteFlowProvider>
