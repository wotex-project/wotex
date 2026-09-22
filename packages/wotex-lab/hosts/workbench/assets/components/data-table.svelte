<script lang="ts">
export interface TableColumn {
  key: string
  label: string
}
export interface TableRow {
  key: string
  values: Record<string, string | number | boolean | null>
}
let { caption, columns, rows }: { caption: string; columns: TableColumn[]; rows: TableRow[] } =
  $props()
</script>

<!-- svelte-ignore a11y_no_noninteractive_tabindex (keyboard scrolling for an overflow region) -->
<div class="wl-table-wrap" role="region" aria-label={`${caption} table`} tabindex="0">
  <table class="wl-table">
    <caption>{caption}</caption>
    <thead><tr>{#each columns as column (column.key)}<th scope="col">{column.label}</th>{/each}</tr></thead>
    <tbody>
      {#each rows as row (row.key)}
        <tr>{#each columns as column (column.key)}<td>{row.values[column.key] ?? ""}</td>{/each}</tr>
      {:else}
        <tr><td colspan={Math.max(1, columns.length)}>No rows</td></tr>
      {/each}
    </tbody>
  </table>
</div>
