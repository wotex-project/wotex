<script lang="ts">
  import type { HTMLInputAttributes } from "svelte/elements"

  let attributes: HTMLInputAttributes = $props()
</script>

<input {...attributes}>
