<script lang="ts">
  import type { IconName } from "$lib/design-system/icons.ts"
  import Icon from "$lib/primitives/icon/icon.svelte"

  let {
    label,
    icon,
    variant = "secondary",
    disabled = false,
    onclick,
  }: {
    label: string
    icon: IconName
    variant?: "primary" | "secondary" | "danger"
    disabled?: boolean
    onclick?: (event: MouseEvent) => void
  } = $props()
</script>

<button
  type="button"
  class="wl-button"
  data-wotex-variant={variant}
  aria-label={label}
  {disabled}
  {onclick}
>
  <Icon name={icon} />
</button>
