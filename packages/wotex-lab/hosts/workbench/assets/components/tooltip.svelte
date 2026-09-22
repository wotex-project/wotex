<script lang="ts">
import type { Snippet } from "svelte"

let { text, children }: { text: string; children?: Snippet } = $props()
</script>

<span class="wl-tooltip" title={text}>{#if children}{@render children()}{/if}</span>
