<script lang="ts">
  import Button from "$lib/primitives/button/button.svelte"
  import Tooltip from "$lib/primitives/tooltip/tooltip.svelte"

  let { text }: { text: string } = $props()
</script>

<Tooltip {text}>
  <Button unstyled type="button" class="wl-button" data-wotex-variant="secondary">{text}</Button>
</Tooltip>
