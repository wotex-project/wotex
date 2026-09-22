<script lang="ts">
export interface ChartSeries {
  id: string
  label: string
}

export interface ChartPoint {
  key: string
  label: string
  values: Record<string, number | null>
}

let {
  title,
  series,
  points,
  oninspect,
}: {
  title: string
  series: ChartSeries[]
  points: ChartPoint[]
  oninspect?: (key: string) => void
} = $props()

const values = $derived(
  points.flatMap((point) => Object.values(point.values).filter((value) => value !== null)),
)
const maximum = $derived(Math.max(1, ...values))
</script>

<figure class="wl-panel">
  <figcaption><strong>{title}</strong></figcaption>
  <div class="wl-chart-bars" aria-hidden="true">
    {#each points as point (point.key)}
      <i
        style:height={`${Math.max(4, (Math.max(0, ...Object.values(point.values).map((value) => value ?? 0)) / maximum) * 100)}%`}
      ></i>
    {/each}
  </div>
  <!-- svelte-ignore a11y_no_noninteractive_tabindex (keyboard scrolling for an overflow region) -->
  <div class="wl-table-wrap" role="region" aria-label={`${title} data table`} tabindex="0">
    <table class="wl-table">
      <caption>{title} values</caption>
      <thead><tr><th scope="col">Point</th>{#each series as item (item.id)}<th scope="col">{item.label}</th>{/each}</tr></thead>
      <tbody>
        {#each points as point (point.key)}
          <tr><th scope="row">{#if oninspect}<button type="button" class="wl-chart-inspect" onclick={() => oninspect?.(point.key)}>{point.label}</button>{:else}{point.label}{/if}</th>{#each series as item (item.id)}<td>{point.values[item.id] ?? "—"}</td>{/each}</tr>
        {:else}<tr><td colspan={series.length + 1}>No chart data</td></tr>{/each}
      </tbody>
    </table>
  </div>
</figure>
