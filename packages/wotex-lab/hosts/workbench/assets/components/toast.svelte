<script lang="ts">
let {
  message,
  kind = "neutral",
  ondismiss,
}: {
  message: string
  kind?: "neutral" | "success" | "warning" | "danger"
  ondismiss?: () => void
} = $props()
</script>

<div class="wl-state" data-wotex-state={kind} role={kind === "danger" ? "alert" : "status"}>
  <p>{message}</p>
  {#if ondismiss}<button type="button" class="wl-button" data-wotex-variant="secondary" onclick={ondismiss}>Dismiss</button>{/if}
</div>
