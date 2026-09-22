<script lang="ts">
import type { IslandTransport, JsonValue } from "./types.js"

interface ChartSeries {
  id: string
  label: string
}

interface ChartPoint {
  key: string
  label: string
  values: Record<string, number | null>
}

let { payload, transport }: { payload: Record<string, JsonValue>; transport: IslandTransport } =
  $props()
const initial = () => ({ payload: { ...payload }, connected: transport.connected() })
const initialState = initial()
let current = $state<Record<string, JsonValue>>(initialState.payload)
let connected = $state(initialState.connected)

export function update(next: Record<string, JsonValue>) {
  current = next
}

export function setConnected(next: boolean) {
  connected = next
}

const title = $derived(String(current.title ?? "Chart"))
const series = $derived((current.series ?? []) as unknown as ChartSeries[])
const points = $derived((current.points ?? []) as unknown as ChartPoint[])
const values = $derived(
  points.flatMap((point) => Object.values(point.values).filter((value) => value !== null)),
)
const maximum = $derived(Math.max(1, ...values))
const inspect = (key: string) => {
  if (connected) void transport.push("inspect", { key }).catch(() => undefined)
}
</script>

<div data-wotex-connected={connected}>
  <figure class="wl-island-panel">
    <figcaption><strong>{title}</strong></figcaption>
    <div class="wl-island-chart-bars" aria-hidden="true">
      {#each points as point (point.key)}
        <i
          style:height={`${Math.max(4, (Math.max(0, ...Object.values(point.values).map((value) => value ?? 0)) / maximum) * 100)}%`}
        ></i>
      {/each}
    </div>
    <!-- svelte-ignore a11y_no_noninteractive_tabindex (keyboard scrolling for an overflow region) -->
    <div class="wl-island-table-wrap" role="region" aria-label={`${title} data table`} tabindex="0">
      <table class="wl-island-table">
        <caption>{title} values</caption>
        <thead><tr><th scope="col">Point</th>{#each series as item (item.id)}<th scope="col">{item.label}</th>{/each}</tr></thead>
        <tbody>
          {#each points as point (point.key)}
            <tr><th scope="row">{#if connected}<button type="button" class="wl-island-chart-inspect" onclick={() => inspect(point.key)}>{point.label}</button>{:else}{point.label}{/if}</th>{#each series as item (item.id)}<td>{point.values[item.id] ?? "—"}</td>{/each}</tr>
          {:else}<tr><td colspan={series.length + 1}>No chart data</td></tr>{/each}
        </tbody>
      </table>
    </div>
  </figure>
</div>
