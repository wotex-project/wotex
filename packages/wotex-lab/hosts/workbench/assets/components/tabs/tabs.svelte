<script lang="ts">
  import { nextItemIndex } from "$lib/primitives/menu-navigation.ts"
  export interface TabItem {
    id: string
    label: string
    content: string
    disabled?: boolean
  }

  let {
    island = false,
    label,
    tabs,
    selected = tabs.find((tab) => !tab.disabled)?.id ?? "",
    onselect,
    disabled = false,
  }: {
    island?: boolean
    label: string
    tabs: TabItem[]
    selected?: string
    onselect?: (id: string) => void
    disabled?: boolean
  } = $props()

  const id = $props.id()

  const choose = (id: string) => {
    if (disabled) {
      return
    }
    selected = id
    onselect?.(id)
  }

  const move = (event: KeyboardEvent, index: number) => {
    if (disabled) {
      return
    }
    const enabled = tabs
      .map((tab, position) => ({
        tab,
        position,
      }))
      .filter(({ tab }) => !tab.disabled)
    const current = enabled.findIndex(({ position }) => position === index)
    const target = nextItemIndex(event.key, current, enabled.length)
    if (target === null) {
      return
    }
    event.preventDefault()
    const next = enabled[target]
    if (!next) {
      return
    }
    choose(next.tab.id)
    document.getElementById(`${id}-tab-${next.tab.id}`)?.focus()
  }

  const prefix = $derived(island ? "wl-island" : "wl")
</script>

<div class={`${prefix}-tabs`}>
  <div role="tablist" aria-label={label}>
    {#each tabs as tab, index (tab.id)}
      <button
        id={`${id}-tab-${tab.id}`}
        type="button"
        role="tab"
        aria-selected={selected === tab.id}
        aria-controls={`${id}-panel-${tab.id}`}
        tabindex={selected === tab.id ? 0 : -1}
        disabled={disabled || tab.disabled}
        onclick={() => choose(tab.id)}
        onkeydown={(event) => move(event, index)}
      >
        {tab.label}
      </button>
    {/each}
  </div>
  {#each tabs as tab (tab.id)}
    <!-- biome-ignore-start lint/a11y/noNoninteractiveTabindex: Tab panels are explicit focus destinations for keyboard navigation. -->
    <div
      id={`${id}-panel-${tab.id}`}
      role="tabpanel"
      aria-labelledby={`${id}-tab-${tab.id}`}
      hidden={selected !== tab.id}
      tabindex="0"
    >
      {tab.content}
    </div>
    <!-- biome-ignore-end lint/a11y/noNoninteractiveTabindex: Preserve the tab-panel keyboard focus destination. -->
  {/each}
</div>
