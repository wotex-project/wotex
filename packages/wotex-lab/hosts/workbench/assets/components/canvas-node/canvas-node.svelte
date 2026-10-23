<script lang="ts">
  import { Handle, type Node, type NodeProps, Position } from "@xyflow/svelte"
  import more from "$lib/components/canvas/assets/ellipsis.svg"
  import flask from "$lib/components/canvas/assets/flask-conical.svg"
  import settings from "$lib/components/canvas/assets/settings-2.svg"
  import thermometer from "$lib/components/canvas/assets/thermometer.svg"
  import zap from "$lib/components/canvas/assets/zap.svg"
  import type { CanvasNode } from "$lib/islands/canvas-model.ts"
  import Button from "$lib/primitives/button/button.svelte"

  type Data = CanvasNode & {
    open: (id: string, event: MouseEvent) => void
    connectable: boolean
  }

  let { data, selected }: NodeProps<Node<Data>> = $props()

  const resolveIcon = () => {
    if (data.kind === "process") {
      return flask
    }
    if (data.id === "thing-thermostat") {
      return thermometer
    }
    if (data.id === "thing-meter") {
      return zap
    }
    return settings
  }

  const icon = $derived(resolveIcon())

  const openMenu = (event: MouseEvent) => data.open(data.id, event)
</script>

<article
  class="wl-canvas-node wl-canvas-subject"
  class:wl-canvas-node-selected={selected}
  class:wl-canvas-process={data.kind === "process"}
>
  <header>
    <img src={icon} width="14" height="14" alt="">
    <strong>{data.title}</strong>
    <Button
      unstyled
      class="nodrag nopan wl-canvas-icon"
      type="button"
      aria-label={`Actions for ${data.title}`}
      onclick={openMenu}
    >
      <img src={more} width="16" height="16" alt="">
    </Button>
  </header>
  <p class="wl-canvas-identity" title={data.identity}>
    {data.kind === "process" ? "Process" : data.identity}
  </p>
  <div class="wl-canvas-reading">
    {#if data.value}
      <span class="wl-canvas-value">{data.value}{data.unit ? ` ${data.unit}` : ""}</span>
    {:else}
      <span class="wl-canvas-status">{data.status}</span>
    {/if}
  </div>
  {#if data.value || data.detail}
    <footer class="wl-canvas-receipt">
      {#if data.value}
        <span class="wl-canvas-status">{data.status}</span>
      {/if}
      {#if data.detail}
        <span class="wl-canvas-detail">{data.detail}</span>
      {/if}
    </footer>
  {/if}
  {#if data.kind === "process"}
    <Handle
      type="target"
      position={Position.Left}
      id="temperature"
      style="top: 31%"
      isConnectable={data.connectable}
      aria-label="Temperature input"
    />
    <Handle
      type="target"
      position={Position.Left}
      id="power"
      style="top: 62%"
      isConnectable={data.connectable}
      aria-label="Power input"
    />
  {:else if data.id === "thing-actuator"}
    <Handle
      type="target"
      position={Position.Left}
      id="input"
      isConnectable={data.connectable}
      aria-label="Proposed Action input"
    />
  {/if}
  {#if data.kind !== "entry"}
    <Handle
      type="source"
      position={Position.Right}
      id="output"
      isConnectable={data.connectable}
      aria-label={data.kind === "process" ? "Action proposal output" : `${data.title} output`}
    />
  {/if}
</article>
