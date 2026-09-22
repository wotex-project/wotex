<script lang="ts">
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
}: { label: string; items: MenuItem[]; open?: boolean; onselect?: (id: string) => void } = $props()

let active = $state(0)
const move = (event: KeyboardEvent) => {
  if (event.key === "ArrowDown") active = (active + 1) % items.length
  else if (event.key === "ArrowUp") active = (active - 1 + items.length) % items.length
  else if (event.key === "Home") active = 0
  else if (event.key === "End") active = items.length - 1
  else if (event.key === "Enter") {
    const item = items[active]
    if (item && !item.disabled) onselect?.(item.id)
    return
  } else return
  event.preventDefault()
  document.querySelector<HTMLElement>(`[data-wotex-menu-index="${active}"]`)?.focus()
}
</script>

<div class="wl-menu">
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
          tabindex={active === index ? 0 : -1}
          disabled={item.disabled}
          onclick={() => onselect?.(item.id)}
          onkeydown={move}
        >{item.label}</button>
      {/each}
    </div>
  {/if}
</div>
