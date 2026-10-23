<script lang="ts">
  import type { MetricSeries } from "./canvas-model.js"
  import { metricGeometry, metricLabel } from "./metric-plot.js"

  let {
    series,
    unit,
    title,
    mark = "line",
  }: {
    series: MetricSeries[]
    unit: string
    title: string
    mark?: "line" | "point" | "area"
  } = $props()
  const geometry = $derived(metricGeometry(series, mark))
</script>

<figure class="wl-metric-plot">
  {#if geometry.available}
    <svg
      viewBox="0 0 330 154"
      role="img"
      aria-label={`${title}, ${unit}. ${geometry.missing} missing samples.`}
    >
      {#each geometry.yTicks as tick}
        <line x1="42" x2="312" y1={tick.y} y2={tick.y} class="wl-plot-grid" />
        <text x="36" y={tick.y + 3} text-anchor="end">{metricLabel(tick.value)}</text>
      {/each}
      {#each geometry.xTicks as tick}
        <text x={tick.x} y="144" text-anchor="middle">{metricLabel(tick.value)}s</text>
      {/each}
      {#each geometry.series as line, index}
        <g class="wl-plot-series" style:opacity={1 - index * 0.065}>
          {#if mark === "area"}
            {#each line.areas as points}
              <polygon {points} class="wl-plot-area" />
            {/each}
          {/if}
          {#if mark !== "point"}
            {#each line.segments as points}
              <polyline {points} stroke-dasharray={index % 2 ? "5 2" : undefined} />
            {/each}
            {#each line.bridges as points}
              <polyline {points} class="wl-plot-gap" />
            {/each}
          {/if}
          {#each line.dots as dot}
            <circle cx={dot.x} cy={dot.y} r="2" />
          {/each}
        </g>
      {/each}
    </svg>
  {:else}
    <div class="wl-plot-empty">No samples</div>
  {/if}
  <figcaption>{unit}{geometry.missing ? ` · ${geometry.missing} missing` : ""}</figcaption>
</figure>
