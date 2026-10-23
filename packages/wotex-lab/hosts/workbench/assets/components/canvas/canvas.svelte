<script lang="ts">
  import { SvelteFlow, useSvelteFlow } from "@xyflow/svelte"
  import { createCanvasState } from "$lib/components/canvas/canvas-state.svelte.ts"
  import CanvasContextMenu from "$lib/components/canvas-context-menu/canvas-context-menu.svelte"
  import CanvasMetric from "$lib/components/canvas-metric/canvas-metric.svelte"
  import CanvasThing from "$lib/components/canvas-node/canvas-node.svelte"
  import CanvasRun from "$lib/components/canvas-run/canvas-run.svelte"
  import CanvasTools from "$lib/components/canvas-tools/canvas-tools.svelte"
  import type { IslandTransport, JsonValue } from "$lib/islands/types.ts"

  let {
    payload,
    transport,
    connected,
  }: {
    payload: Record<string, JsonValue>
    transport: IslandTransport
    connected: boolean
  } = $props()

  const readPayload = () => payload

  const readConnected = () => connected

  const readTransport = () => transport

  const state = createCanvasState({
    readPayload,
    readConnected,
    readTransport,
    flow: useSvelteFlow(),
  })
  const nodeTypes = { thing: CanvasThing, metric: CanvasMetric, run_result: CanvasRun }
</script>

<div
  bind:this={state.root}
  bind:clientWidth={state.width}
  bind:clientHeight={state.height}
  class="wl-connected-canvas"
  data-wotex-connected={connected}
  style:background-size={`${104 * state.viewport.zoom}px ${104 * state.viewport.zoom}px`}
  style:background-position={`${state.viewport.x}px ${state.viewport.y}px`}
>
  {#if state.width > 0 && state.height > 0}
    <SvelteFlow
      bind:nodes={state.nodes}
      bind:edges={state.edges}
      bind:viewport={state.viewport}
      {nodeTypes}
      width={state.width}
      height={state.height}
      nodesConnectable={connected}
      isValidConnection={state.validConnection}
      onbeforeconnect={state.proposeConnection}
      onedgeclick={state.inspectEdge}
      onedgecontextmenu={state.openEdgeMenu}
      deleteKey={null}
      minZoom={0.25}
      maxZoom={2}
      fitView={!state.savedViewport}
      initialViewport={state.savedViewport}
      fitViewOptions={{
        padding: 0.2,
        maxZoom: 1,
      }}
      nodeExtent={[
        [-20000, -20000],
        [20000, 20000],
      ]}
      onmove={state.markUnsaved}
      onnodedrag={state.markUnsaved}
      panOnDrag={state.pan ? true : [1, 2]}
      selectionOnDrag={!state.pan}
      attributionPosition="bottom-left"
      onnodecontextmenu={state.openNodeMenu}
      onpaneclick={state.dismissMenu}
    />
  {/if}
  <CanvasTools
    pan={state.pan}
    {connected}
    saving={state.saving}
    saved={state.saved}
    onselect={state.selectTool}
  />
  {#if state.menu}
    <CanvasContextMenu
      {connected}
      x={state.menu.x}
      y={state.menu.y}
      menuItems={state.menuItems}
      label={state.menuLabel}
      bind:firstAction={state.firstAction}
      onaction={state.chooseMenuAction}
      onclose={state.closeMenu}
    />
  {/if}
  {#if !connected}
    <span class="wl-canvas-notice" role="status">Disconnected</span>
  {/if}
  {#if state.error}
    <span class="wl-canvas-notice" role="alert">{state.error}</span>
  {/if}
</div>
