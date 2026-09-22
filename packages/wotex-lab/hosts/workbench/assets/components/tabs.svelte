<script lang="ts">
export interface TabItem {
  id: string
  label: string
  content: string
  disabled?: boolean
}

let {
  label,
  tabs,
  selected = tabs.find((tab) => !tab.disabled)?.id ?? "",
  onselect,
  disabled = false,
}: {
  label: string
  tabs: TabItem[]
  selected?: string
  onselect?: (id: string) => void
  disabled?: boolean
} = $props()

const choose = (id: string) => {
  if (disabled) return
  selected = id
  onselect?.(id)
}

const move = (event: KeyboardEvent, index: number) => {
  if (disabled) return
  const enabled = tabs
    .map((tab, position) => ({ tab, position }))
    .filter(({ tab }) => !tab.disabled)
  const current = enabled.findIndex(({ position }) => position === index)
  let target = current
  if (event.key === "ArrowRight" || event.key === "ArrowDown")
    target = (current + 1) % enabled.length
  else if (event.key === "ArrowLeft" || event.key === "ArrowUp")
    target = (current - 1 + enabled.length) % enabled.length
  else if (event.key === "Home") target = 0
  else if (event.key === "End") target = enabled.length - 1
  else return
  event.preventDefault()
  const next = enabled[target]
  if (!next) return
  choose(next.tab.id)
  document.getElementById(`wl-tab-${next.tab.id}`)?.focus()
}
</script>

<div class="wl-tabs">
  <div role="tablist" aria-label={label}>
    {#each tabs as tab, index (tab.id)}
      <button
        id={`wl-tab-${tab.id}`}
        type="button"
        role="tab"
        aria-selected={selected === tab.id}
        aria-controls={`wl-panel-${tab.id}`}
        tabindex={selected === tab.id ? 0 : -1}
        disabled={disabled || tab.disabled}
        onclick={() => choose(tab.id)}
        onkeydown={(event) => move(event, index)}
      >{tab.label}</button>
    {/each}
  </div>
  {#each tabs as tab (tab.id)}
    <div
      id={`wl-panel-${tab.id}`}
      role="tabpanel"
      aria-labelledby={`wl-tab-${tab.id}`}
      hidden={selected !== tab.id}
      tabindex="0"
    >{tab.content}</div>
  {/each}
</div>
