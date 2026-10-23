<script lang="ts">
  import Menu, { type MenuItem } from "$lib/components/menu/menu.svelte"

  let { label, items, open = true }: { label: string; items: MenuItem[]; open?: boolean } = $props()
  let count = $state(0)
  let selected = $state("")

  const select = (id: string) => {
    selected = id
    count += 1
  }
</script>

<Menu {label} {items} {open} onselect={select} />
<output aria-live="polite">{selected} {count}</output>
