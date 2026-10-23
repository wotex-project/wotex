<script lang="ts">
  import { type Node, type NodeProps, NodeResizer } from "@xyflow/svelte"
  import more from "$lib/components/canvas/assets/ellipsis.svg"
  import MetricPlot from "$lib/components/metric-plot/metric-plot.svelte"
  import type { CanvasMetricPin } from "$lib/islands/canvas-model.ts"

  type Data = CanvasMetricPin & {
    open: (id: string, event: MouseEvent) => void
    changed: () => void
  }
  let { data, selected }: NodeProps<Node<Data>> = $props()
  const time = $derived(new Date(data.end_ms).toISOString().slice(11, 19))
</script>

<NodeResizer
  isVisible={selected}
  minWidth={300}
  maxWidth={800}
  minHeight={200}
  maxHeight={600}
  onResizeStart={data.changed}
/>

<article class="wl-canvas-node wl-canvas-metric" class:wl-canvas-node-selected={selected}>
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
  <p class="wl-canvas-identity">{data.source} · {data.range} · {data.aggregation}</p>
  <MetricPlot series={data.series} unit={data.unit} title={data.title} />
  <footer>
    <p class="wl-canvas-detail">{data.state} · {time} UTC</p>
    <details class="nodrag nopan wl-pin-data">
      <summary>Data</summary>
      <div class="wl-pin-data-scroll">
        <table>
          <caption>
            {data.title}
            · seconds before range end
          </caption>
          <thead>
            <tr>
              <th>Series</th>
              <th>Offset (s)</th>
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
