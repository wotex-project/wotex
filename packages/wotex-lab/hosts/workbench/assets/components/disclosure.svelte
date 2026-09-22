<script lang="ts">
import type { Snippet } from "svelte"

let {
  summary,
  open = false,
  children,
}: { summary: string; open?: boolean; children: Snippet } = $props()
</script>

<details bind:open><summary>{summary}</summary><div>{@render children()}</div></details>
