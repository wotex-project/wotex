<script lang="ts">
import { tick } from "svelte"
import type { TableColumn, TableRow } from "./data-table.svelte"

let {
  label,
  columns,
  rows,
  onselect,
  onactivate,
}: {
  label: string
  columns: TableColumn[]
  rows: TableRow[]
  onselect?: (key: string) => void
  onactivate?: (key: string) => void
} = $props()

let activeRow = $state(0)
let activeColumn = $state(0)
let gridRoot: HTMLElement

const focusCell = async () => {
  await tick()
  gridRoot.querySelector<HTMLElement>(`[data-wotex-grid-cell="${activeRow}:${activeColumn}"]`)?.focus()
}

const move = (event: KeyboardEvent, row: number, column: number) => {
  let nextRow = row
  let nextColumn = column
  if (event.key === "ArrowRight") nextColumn = Math.min(columns.length - 1, column + 1)
  else if (event.key === "ArrowLeft") nextColumn = Math.max(0, column - 1)
  else if (event.key === "ArrowDown") nextRow = Math.min(rows.length - 1, row + 1)
  else if (event.key === "ArrowUp") nextRow = Math.max(0, row - 1)
  else if (event.key === "Home") nextColumn = 0
  else if (event.key === "End") nextColumn = Math.max(0, columns.length - 1)
  else if (event.key === "Enter") {
    const selected = rows[row]
    if (selected) onactivate?.(selected.key)
    return
  } else return
  event.preventDefault()
  activeRow = nextRow
  activeColumn = nextColumn
  const selected = rows[nextRow]
  if (selected) onselect?.(selected.key)
  void focusCell()
}
</script>

<div
  bind:this={gridRoot}
  class="wl-grid"
  role="grid"
  aria-label={label}
  aria-rowcount={rows.length + 1}
  aria-colcount={columns.length}
  style={`--wotex-grid-columns:${Math.max(1, columns.length)}`}
>
  <div role="row" class="wl-grid-row wl-grid-header">
    {#each columns as column (column.key)}<div role="columnheader">{column.label}</div>{/each}
  </div>
  {#each rows as row, rowIndex (row.key)}
    <div role="row" class="wl-grid-row" aria-rowindex={rowIndex + 2}>
      {#each columns as column, columnIndex (column.key)}
        <!-- svelte-ignore a11y_no_static_element_interactions (ARIA grid roving focus) -->
        <div
          role="gridcell"
          aria-colindex={columnIndex + 1}
          tabindex={activeRow === rowIndex && activeColumn === columnIndex ? 0 : -1}
          data-wotex-grid-cell={`${rowIndex}:${columnIndex}`}
          onfocus={() => {
            activeRow = rowIndex
            activeColumn = columnIndex
            onselect?.(row.key)
          }}
          onkeydown={(event) => move(event, rowIndex, columnIndex)}
          ondblclick={() => onactivate?.(row.key)}
        >{row.values[column.key] ?? ""}</div>
      {/each}
    </div>
  {:else}
    <p role="status">No rows</p>
  {/each}
</div>
