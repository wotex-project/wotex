<script lang="ts">
  import type { TabItem } from "$lib/components/tabs/tabs.svelte"
  import Button from "$lib/primitives/button/button.svelte"

  let {
    id,
    tab,
    index,
    selected,
    disabled,
    onselect,
    onmove,
  }: {
    id: string
    tab: TabItem
    index: number
    selected: boolean
    disabled: boolean
    onselect: (id: string) => void
    onmove: (event: KeyboardEvent, index: number) => void
  } = $props()

  const choose = () => onselect(tab.id)

  const move = (event: KeyboardEvent) => onmove(event, index)
</script>

<Button
  unstyled
  id={`${id}-tab-${tab.id}`}
  type="button"
  role="tab"
  aria-selected={selected}
  aria-controls={`${id}-panel-${tab.id}`}
  tabindex={selected ? 0 : -1}
  disabled={disabled || tab.disabled}
  onclick={choose}
  onkeydown={move}
>
  {tab.label}
</Button>
