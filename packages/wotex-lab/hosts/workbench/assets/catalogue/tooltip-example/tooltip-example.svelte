<script lang="ts">
  import Tooltip from "$lib/primitives/tooltip/tooltip.svelte"

  let { text }: { text: string } = $props()
</script>

<Tooltip {text}>
  <button type="button" class="wl-button" data-wotex-variant="secondary">{text}</button>
</Tooltip>
