<script lang="ts">
import type { IslandTransport, JsonValue } from "./types.js"

interface TabItem {
  id: string
  label: string
  content: string
  disabled?: boolean
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

const label = $derived(String(current.label ?? "Tabs"))
const tabs = $derived((current.tabs ?? []) as unknown as TabItem[])
let selected = $derived(String(current.selected ?? tabs.find((tab) => !tab.disabled)?.id ?? ""))

const choose = (id: string) => {
  if (!connected) return
  selected = id
  void transport.push("select", { id }).catch(() => undefined)
}

const move = (event: KeyboardEvent, index: number) => {
  if (!connected) return
  const enabled = tabs
    .map((tab, position) => ({ tab, position }))
    .filter(({ tab }) => !tab.disabled)
  const currentIndex = enabled.findIndex(({ position }) => position === index)
  let target = currentIndex
  if (event.key === "ArrowRight" || event.key === "ArrowDown")
    target = (currentIndex + 1) % enabled.length
  else if (event.key === "ArrowLeft" || event.key === "ArrowUp")
    target = (currentIndex - 1 + enabled.length) % enabled.length
  else if (event.key === "Home") target = 0
  else if (event.key === "End") target = enabled.length - 1
  else return
  event.preventDefault()
  const next = enabled[target]
  if (!next) return
  choose(next.tab.id)
  document.getElementById(`wotex-tab-${next.tab.id}`)?.focus()
}
</script>

<div data-wotex-connected={connected} class="wl-island-tabs">
  <div role="tablist" aria-label={label}>
    {#each tabs as tab, index (tab.id)}
      <button
        id={`wotex-tab-${tab.id}`}
        type="button"
        role="tab"
        aria-selected={selected === tab.id}
        aria-controls={`wotex-panel-${tab.id}`}
        tabindex={selected === tab.id ? 0 : -1}
        disabled={!connected || tab.disabled}
        onclick={() => choose(tab.id)}
        onkeydown={(event) => move(event, index)}
      >{tab.label}</button>
    {/each}
  </div>
  {#each tabs as tab (tab.id)}
    <div
      id={`wotex-panel-${tab.id}`}
      role="tabpanel"
      aria-labelledby={`wotex-tab-${tab.id}`}
      hidden={selected !== tab.id}
      tabindex="0"
    >{tab.content}</div>
  {/each}
</div>
