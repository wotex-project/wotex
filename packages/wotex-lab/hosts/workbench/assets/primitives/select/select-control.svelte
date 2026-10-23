<script lang="ts">
  import type { Snippet } from "svelte"
  import type { HTMLSelectAttributes } from "svelte/elements"

  let { children, ...attributes }: HTMLSelectAttributes & { children?: Snippet } = $props()
</script>

<select {...attributes}>
  {@render children?.()}
</select>
