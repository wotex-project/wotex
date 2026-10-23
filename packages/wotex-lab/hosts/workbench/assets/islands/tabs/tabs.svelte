<script lang="ts">
  import Tabs, { type TabItem } from "$lib/components/tabs/tabs.svelte"
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

  const label = $derived(String(current.label ?? "Tabs"))
  const tabs = $derived((current.tabs ?? []) as unknown as TabItem[])
  const selected = $derived(String(current.selected ?? tabs.find((tab) => !tab.disabled)?.id ?? ""))

  const select = (id: string) => {
    if (connected) {
      void transport.push("select", { id }).catch(() => undefined)
    }
  }
</script>

<div data-wotex-connected={connected}>
  <Tabs {label} {tabs} island {selected} disabled={!connected} onselect={select} />
</div>
