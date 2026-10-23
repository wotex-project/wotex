<script lang="ts">
  import { nextItemIndex } from "$lib/primitives/menu-navigation.ts"
  export interface MenuItem {
    id: string
    label: string
    disabled?: boolean
  }

  let {
    label,
    items,
    open = false,
    onselect,
  }: {
    label: string
    items: MenuItem[]
    open?: boolean
    onselect?: (id: string) => void
  } = $props()

  let active = $state(0)
  let root = $state<HTMLDivElement>()

  const choose = (id: string) => {
    const index = items.findIndex((item) => item.id === id && !item.disabled)
    if (index < 0) {
      return
    }
    active = index
    onselect?.(id)
  }

  const move = (event: KeyboardEvent & { currentTarget: HTMLButtonElement }) => {
    const buttons = [...(root?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") ?? [])]
    const next = nextItemIndex(event.key, buttons.indexOf(event.currentTarget), buttons.length)
    if (next === null) {
      return
    }
    event.preventDefault()
    const button = buttons[next]
    if (button) {
      active = Number(button.dataset.wotexMenuIndex)
      button.focus()
    }
  }
</script>

<div bind:this={root} class="wl-menu">
  <strong>{label}</strong>
  {#if open}
    <div role="menu" aria-label={label}>
      {#each items as item, index (item.id)}
        <button
          type="button"
          role="menuitem"
          class="wl-button"
          data-wotex-variant="secondary"
          data-wotex-menu-index={index}
          tabindex={(items[active]?.disabled
            ? items.findIndex((candidate) => !candidate.disabled)
            : active) === index
            ? 0
            : -1}
          disabled={item.disabled}
          onclick={() => choose(item.id)}
          onkeydown={move}
        >
          {item.label}
        </button>
      {/each}
    </div>
  {/if}
</div>
