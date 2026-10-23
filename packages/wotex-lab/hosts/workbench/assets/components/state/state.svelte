<script lang="ts">
  import Button from "$lib/primitives/button/button.svelte"

  let {
    title,
    message,
    state = "empty",
    onretry,
  }: {
    title: string
    message: string
    state?: "empty" | "error" | "loading" | "disconnected"
    onretry?: () => void
  } = $props()
</script>

<section class="wl-state" data-wotex-state={state} role={state === "error" ? "alert" : "status"}>
  <h2>{title}</h2>
  <p>{message}</p>
  {#if onretry}
    <Button
      unstyled
      type="button"
      class="wl-button"
      data-wotex-variant="secondary"
      onclick={onretry}
    >
      Retry
    </Button>
  {/if}
</section>
