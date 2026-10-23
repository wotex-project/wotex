<script lang="ts">
  import DataGrid from "$lib/components/data-grid/data-grid.svelte"
  import type { TableColumn, TableRow } from "$lib/components/data-table/data-table.svelte"
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

  const label = $derived(String(current.label ?? "Data grid"))
  const columns = $derived((current.columns ?? []) as unknown as TableColumn[])
  const rows = $derived((current.rows ?? []) as unknown as TableRow[])

  const select = (key: string) => {
    if (connected) {
      void transport.push("select", { key }).catch(() => undefined)
    }
  }

  const activate = (key: string) => {
    if (connected) {
      void transport.push("activate", { key }, crypto.randomUUID()).catch(() => undefined)
    }
  }
</script>

<div data-wotex-connected={connected}>
  <DataGrid
    {label}
    {columns}
    {rows}
    island
    disabled={!connected}
    onselect={select}
    onactivate={activate}
  />
</div>
