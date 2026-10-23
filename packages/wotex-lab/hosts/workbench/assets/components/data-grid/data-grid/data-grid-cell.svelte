<script lang="ts">
  import type { TableColumn, TableRow } from "$lib/components/data-table/data-table.svelte"

  let {
    row,
    column,
    rowIndex,
    columnIndex,
    active,
    onfocus,
    onmove,
    onactivate,
  }: {
    row: TableRow
    column: TableColumn
    rowIndex: number
    columnIndex: number
    active: boolean
    onfocus: (key: string, row: number, column: number) => void
    onmove: (event: KeyboardEvent, row: number, column: number) => void
    onactivate: (key: string) => void
  } = $props()

  const focus = () => onfocus(row.key, rowIndex, columnIndex)

  const move = (event: KeyboardEvent) => onmove(event, rowIndex, columnIndex)

  const activate = () => onactivate(row.key)
</script>

<!-- svelte-ignore a11y_no_static_element_interactions (ARIA grid roving focus) -->
<!-- biome-ignore lint/a11y/useSemanticElements: Explicit ARIA grid semantics preserve the roving-cell interaction model. -->
<div
  role="gridcell"
  aria-colindex={columnIndex + 1}
  tabindex={active ? 0 : -1}
  data-wotex-grid-cell={`${rowIndex}:${columnIndex}`}
  onfocus={focus}
  onkeydown={move}
  ondblclick={activate}
>
  {row.values[column.key] ?? ""}
</div>
