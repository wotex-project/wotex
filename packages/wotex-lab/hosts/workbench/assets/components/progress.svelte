<script lang="ts">
let { label, value }: { label: string; value?: number } = $props()
</script>

<label class="wl-control">{label}<progress class="wl-progress" {value} max="100">{value ?? label}</progress></label>
