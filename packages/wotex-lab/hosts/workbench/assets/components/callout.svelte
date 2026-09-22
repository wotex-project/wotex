<script lang="ts">
import type { Snippet } from "svelte"

let {
  title,
  kind = "note",
  children,
}: {
  title: string
  kind?: "note" | "tip" | "warning" | "danger"
  children?: Snippet
} = $props()
</script>

<aside class="wl-callout" data-wotex-kind={kind} role="note">
  <strong>{kind[0]?.toUpperCase()}{kind.slice(1)}: {title}</strong>
  {#if children}{@render children()}{/if}
</aside>
