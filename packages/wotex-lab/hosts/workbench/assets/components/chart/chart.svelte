<script lang="ts">
  import Button from "$lib/primitives/button/button.svelte"

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
    island = false,
    title,
    series,
    points,
    oninspect,
  }: {
    island?: boolean
    title: string
    series: ChartSeries[]
    points: ChartPoint[]
    oninspect?: (key: string) => void
  } = $props()

  const values = $derived(
    points.flatMap((point) => Object.values(point.values).filter((value) => value !== null)),
  )
  const maximum = $derived(Math.max(1, ...values))

  const barHeight = (point: ChartPoint) =>
    `${Math.max(4, (Math.max(0, ...Object.values(point.values).map((value) => value ?? 0)) / maximum) * 100)}%`

  const inspect = (key: string) => () => oninspect?.(key)

  const prefix = $derived(island ? "wl-island" : "wl")
</script>

<figure class={`${prefix}-panel`}>
  <figcaption><strong>{title}</strong></figcaption>
  <div class={`${prefix}-chart-bars`} aria-hidden="true">
    {#each points as point (point.key)}
      <i style:height={barHeight(point)}></i>
    {/each}
  </div>
  <!-- svelte-ignore a11y_no_noninteractive_tabindex (keyboard scrolling for an overflow region) -->
  <!-- biome-ignore lint/a11y/noNoninteractiveTabindex lint/a11y/useSemanticElements: The labelled overflow region must support keyboard scrolling. -->
  <div class={`${prefix}-table-wrap`} role="region" aria-label={`${title} data table`} tabindex="0">
    <table class={`${prefix}-table`}>
      <caption>
        {title}
        values
      </caption>
      <thead>
        <tr>
          <th scope="col">Point</th>
          {#each series as item (item.id)}
            <th scope="col">{item.label}</th>
          {/each}
        </tr>
      </thead>
      <tbody>
        {#each points as point (point.key)}
          <tr>
            <th scope="row">
              {#if oninspect}
                <Button
                  unstyled
                  type="button"
                  class={`${prefix}-chart-inspect`}
                  onclick={inspect(point.key)}
                >
                  {point.label}
                </Button>
              {:else}
                {point.label}
              {/if}
            </th>
            {#each series as item (item.id)}
              <td>{point.values[item.id] ?? "—"}</td>
            {/each}
          </tr>
        {:else}
          <tr>
            <td colspan={series.length + 1}>No chart data</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</figure>
