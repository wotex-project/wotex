<script lang="ts">
  import Chart, { type ChartPoint, type ChartSeries } from "$lib/components/chart/chart.svelte"
  import type { IslandTransport, JsonValue } from "$lib/islands/types.ts"

  let { payload, transport }: { payload: Record<string, JsonValue>; transport: IslandTransport } =
    $props()

  const initial = () => ({ payload: { ...payload }, connected: transport.connected() })

  const initialState = initial()
  let current = $state(initialState.payload)
  let connected = $state(initialState.connected)

  export const update = (next: Record<string, JsonValue>) => {
    current = next
  }

  export const setConnected = (next: boolean) => {
    connected = next
  }

  const title = $derived(String(current.title ?? "Chart"))
  const series = $derived((current.series ?? []) as unknown as ChartSeries[])
  const points = $derived((current.points ?? []) as unknown as ChartPoint[])

  const inspect = (key: string) => {
    if (connected) {
      void transport.push("inspect", { key }).catch(() => undefined)
    }
  }
</script>

<div data-wotex-connected={connected}>
  <Chart {title} {series} {points} island oninspect={connected ? inspect : undefined} />
</div>
