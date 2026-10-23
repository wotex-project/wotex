<script lang="ts">
  import { tick } from "svelte"
  import DataGridCell from "$lib/components/data-grid/data-grid/data-grid-cell.svelte"
  import type { TableColumn, TableRow } from "$lib/components/data-table/data-table.svelte"

  let {
    island = false,
    disabled = false,
    label,
    columns,
    rows,
    onselect,
    onactivate,
  }: {
    island?: boolean
    disabled?: boolean
    label: string
    columns: TableColumn[]
    rows: TableRow[]
    onselect?: (key: string) => void
    onactivate?: (key: string) => void
  } = $props()

  let activeRow = $state(0)
  let activeColumn = $state(0)
  let gridRoot = $state<HTMLElement>()

  const focusCell = async () => {
    await tick()
    gridRoot
      ?.querySelector<HTMLElement>(`[data-wotex-grid-cell="${activeRow}:${activeColumn}"]`)
      ?.focus()
  }

  const move = (event: KeyboardEvent, row: number, column: number) => {
    let nextRow = row
    let nextColumn = column
    if (event.key === "ArrowRight") {
      nextColumn = Math.min(columns.length - 1, column + 1)
    } else if (event.key === "ArrowLeft") {
      nextColumn = Math.max(0, column - 1)
    } else if (event.key === "ArrowDown") {
      nextRow = Math.min(rows.length - 1, row + 1)
    } else if (event.key === "ArrowUp") {
      nextRow = Math.max(0, row - 1)
    } else if (event.key === "Home") {
      nextColumn = 0
    } else if (event.key === "End") {
      nextColumn = Math.max(0, columns.length - 1)
    } else if (event.key === "Enter") {
      const selected = rows[row]
      if (selected) {
        if (!disabled) {
          onactivate?.(selected.key)
        }
      }
      return
    } else {
      return
    }
    event.preventDefault()
    activeRow = nextRow
    activeColumn = nextColumn
    const selected = rows[nextRow]
    if (selected) {
      if (!disabled) {
        onselect?.(selected.key)
      }
    }
    void focusCell()
  }

  const focusRow = (key: string, row: number, column: number) => {
    activeRow = row
    activeColumn = column
    if (!disabled) {
      onselect?.(key)
    }
  }

  const activateRow = (key: string) => {
    if (!disabled) {
      onactivate?.(key)
    }
  }

  const isActive = (row: number, column: number) =>
    Math.min(activeRow, rows.length - 1) === row &&
    Math.min(activeColumn, columns.length - 1) === column

  const prefix = $derived(island ? "wl-island" : "wl")
</script>

{#if columns.length === 0 || rows.length === 0}
  <p role="status">No rows</p>
{:else}
  <!-- biome-ignore lint/a11y/useSemanticElements: Explicit ARIA grid semantics preserve the roving-cell interaction model. -->
  <div
    bind:this={gridRoot}
    class={`${prefix}-grid`}
    role="grid"
    aria-label={label}
    aria-disabled={disabled}
    aria-rowcount={rows.length + 1}
    aria-colcount={columns.length}
    style={`--wotex-grid-columns:${Math.max(1, columns.length)}`}
  >
    <!-- biome-ignore lint/a11y/useFocusableInteractive lint/a11y/useSemanticElements: The ARIA grid keeps roving focus on cells rather than rows and column headers. -->
    <div role="row" class={`${prefix}-grid-row ${prefix}-grid-header`}>
      {#each columns as column (column.key)}
        <!-- biome-ignore lint/a11y/useFocusableInteractive lint/a11y/useSemanticElements: The ARIA grid keeps roving focus on cells rather than rows and column headers. -->
        <div role="columnheader">{column.label}</div>
      {/each}
    </div>
    {#each rows as row, rowIndex (row.key)}
      <!-- biome-ignore lint/a11y/useFocusableInteractive lint/a11y/useSemanticElements: The ARIA grid keeps roving focus on cells rather than rows and column headers. -->
      <div role="row" class={`${prefix}-grid-row`} aria-rowindex={rowIndex + 2}>
        {#each columns as column, columnIndex (column.key)}
          <DataGridCell
            {row}
            {column}
            {rowIndex}
            {columnIndex}
            active={isActive(rowIndex, columnIndex)}
            onfocus={focusRow}
            onmove={move}
            onactivate={activateRow}
          />
        {/each}
      </div>
    {/each}
  </div>
{/if}
