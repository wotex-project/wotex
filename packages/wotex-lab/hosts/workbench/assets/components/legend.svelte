<script lang="ts">
export interface LegendItem {
  id: string
  label: string
  color: string
}

let { label = "Legend", items }: { label?: string; items: LegendItem[] } = $props()
</script>

<section class="wl-legend" aria-label={label}>
  <ul>{#each items as item (item.id)}<li><i aria-hidden="true" style:background={item.color}></i>{item.label}</li>{/each}</ul>
</section>
