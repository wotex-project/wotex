<script lang="ts">
  import { type Node, type NodeProps, NodeResizer } from "@xyflow/svelte"
  import more from "$lib/components/canvas/assets/ellipsis.svg"
  import MetricPlot from "$lib/components/metric-plot/metric-plot.svelte"
  import type { CanvasRunPin } from "$lib/islands/canvas-model.ts"
  import Button from "$lib/primitives/button/button.svelte"

  type Data = CanvasRunPin & {
    open: (id: string, event: MouseEvent) => void
    changed: () => void
  }

  let { data, selected }: NodeProps<Node<Data>> = $props()

  const openMenu = (event: MouseEvent) => data.open(data.id, event)
</script>

<NodeResizer
  isVisible={selected}
  minWidth={300}
  maxWidth={800}
  minHeight={200}
  maxHeight={600}
  onResizeStart={data.changed}
/>

<article
  class="wl-canvas-node wl-canvas-metric wl-canvas-run"
  class:wl-canvas-node-selected={selected}
>
  <header>
    <strong title={data.title}>{data.title}</strong
    ><Button
      unstyled
      type="button"
      class="nodrag nopan wl-canvas-icon"
      aria-label={`Actions for ${data.title}`}
      onclick={openMenu}
    >
      <img src={more} alt="">
    </Button>
  </header>
  <p class="wl-canvas-identity">{data.run_id} · {data.state}</p>
  {#if data.outcome}
    <div class="wl-run-pin-value">
      <small>{data.outcome.label}</small
      ><strong>{data.outcome.value}{data.outcome.unit ? ` ${data.outcome.unit}` : ""}</strong>
    </div>
  {/if}
  <MetricPlot series={data.series} unit={data.unit} title={data.title} mark={data.mark} />
  <footer>
    <details class="nodrag nopan wl-pin-data">
      <summary>Data</summary>
      <div class="wl-pin-data-scroll">
        <table>
          <caption>
            {data.title}
            · elapsed seconds
          </caption>
          <thead>
            <tr>
              <th>Series</th>
              <th>Elapsed (s)</th>
              <th>{data.unit}</th>
            </tr>
          </thead>
          <tbody>
            {#each data.series as s}
              {#each s.points as point}
                <tr>
                  <th>{s.name}</th>
                  <td>{point[0]}</td>
                  <td>{point[1] ?? "—"}</td>
                </tr>
              {/each}
            {/each}
          </tbody>
        </table>
      </div>
    </details>
  </footer>
</article>
