<script lang="ts">
  import type { ContextMenuItem } from "$lib/components/canvas-context-menu/context-menu.ts"
  import Button from "$lib/primitives/button/button.svelte"
  import { nextItemIndex } from "$lib/primitives/menu-navigation.ts"

  let {
    label,
    x = 0,
    y = 0,
    menuItems,
    connected = true,
    firstAction = $bindable<HTMLButtonElement | undefined>(),
    onaction,
    onclose,
  }: {
    label: string
    x?: number
    y?: number
    menuItems: ContextMenuItem[]
    connected?: boolean
    firstAction?: HTMLButtonElement
    onaction: (id: string) => void
    onclose: () => void
  } = $props()

  const choose = (id: string) => {
    if (connected) {
      onaction(id)
    }
  }

  const bindFirstAction = (index: number) => (element: HTMLButtonElement) => {
    if (index === 0) {
      firstAction = element
    }
    return () => {
      if (firstAction === element) {
        firstAction = undefined
      }
    }
  }

  const move = (event: KeyboardEvent & { currentTarget: HTMLDivElement }) => {
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      onclose()
      return
    }
    if (event.key === "Tab") {
      onclose()
      return
    }
    const items = [
      ...event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)"),
    ]
    const next = nextItemIndex(
      event.key,
      items.indexOf(document.activeElement as HTMLButtonElement),
      items.length,
    )
    if (next !== null) {
      event.preventDefault()
      items[next]?.focus()
    }
  }

  const selectItem = (id: string) => () => choose(id)
</script>

<div
  class="wl-canvas-context"
  role="menu"
  tabindex="-1"
  aria-label={label}
  style:left={`${x}px`}
  style:top={`${y}px`}
  onkeydown={move}
>
  {#each menuItems as item, index (item.id)}
    <Button
      unstyled
      {@attach bindFirstAction(index)}
      type="button"
      role="menuitem"
      disabled={!connected || item.disabled}
      onclick={selectItem(item.id)}
    >
      {item.label}
    </Button>
  {/each}
</div>
