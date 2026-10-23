<script lang="ts">
  import { type IconName, icons } from "$lib/design-system/icons.ts"

  let {
    name,
    label,
    size = 20,
  }: {
    name: IconName
    label?: string
    size?: number
  } = $props()
</script>

<svg
  viewBox="0 0 24 24"
  width={size}
  height={size}
  aria-label={label}
  aria-hidden={label ? undefined : "true"}
  focusable="false"
  fill="currentColor"
>
  <path d={icons[name]}></path>
</svg>
