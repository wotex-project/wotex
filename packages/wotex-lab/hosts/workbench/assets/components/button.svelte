<script lang="ts">
import type { Snippet } from "svelte"

let {
  label,
  variant = "primary",
  disabled = false,
  loading = false,
  children,
  onclick,
}: {
  label: string
  variant?: "primary" | "secondary" | "danger"
  disabled?: boolean
  loading?: boolean
  children?: Snippet
  onclick?: (event: MouseEvent) => void
} = $props()
</script>

<button
  type="button"
  class="wl-button"
  data-wotex-variant={variant}
  {disabled}
  aria-busy={loading || undefined}
  {onclick}
>
  {#if children}{@render children()}{:else}{label}{/if}
</button>
