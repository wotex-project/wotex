<script lang="ts">
let {
  label,
  kind = "neutral",
}: { label: string; kind?: "neutral" | "success" | "warning" | "danger" } = $props()
</script>

<span class="wl-status" data-wotex-kind={kind}>{label}</span>
