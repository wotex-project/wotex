<script lang="ts">
import type { Snippet } from "svelte"

let {
  id,
  title,
  open = false,
  children,
  onclose,
}: {
  id: string
  title: string
  open?: boolean
  children?: Snippet
  onclose?: () => void
} = $props()
</script>

<dialog {id} {open} class="wl-dialog" aria-labelledby={`${id}-title`} onclose={() => onclose?.()}>
  <h2 id={`${id}-title`}>{title}</h2>
  {#if children}{@render children()}{/if}
</dialog>
