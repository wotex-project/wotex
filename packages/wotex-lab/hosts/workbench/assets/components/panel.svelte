<script lang="ts">
import type { Snippet } from "svelte"

let { title, children }: { title: string; children?: Snippet } = $props()
</script>

<section class="wl-panel" aria-label={title}>
  <h2>{title}</h2>
  {#if children}{@render children()}{/if}
</section>
