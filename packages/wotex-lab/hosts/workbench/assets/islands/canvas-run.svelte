<script lang="ts">
  import { type Node, type NodeProps, NodeResizer } from "@xyflow/svelte"
  import more from "./canvas-assets/ellipsis.svg"
  import type { CanvasRunPin } from "./canvas-model.js"
  import MetricPlot from "./metric-plot.svelte"

  type Data = CanvasRunPin & {
    open: (id: string, event: MouseEvent) => void
    changed: () => void
  }
  let { data, selected }: NodeProps<Node<Data>> = $props()
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
    ><button
      type="button"
      class="nodrag nopan wl-canvas-icon"
      aria-label={`Actions for ${data.title}`}
      onclick={(e) => data.open(data.id, e)}
    >
      <img src={more} alt="">
    </button>
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
