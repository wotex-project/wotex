<script lang="ts">
  import "$lib/components/canvas/canvas.css"
  import CanvasContextMenu from "$lib/components/canvas-context-menu/canvas-context-menu.svelte"
  import { contextMenuItems } from "$lib/components/canvas-context-menu/context-menu.ts"

  let {
    kind,
    label,
    operations = [],
  }: {
    kind: Parameters<typeof contextMenuItems>[0]
    label: string
    operations?: ("read" | "observe" | "pause")[]
  } = $props()
  let selected = $state("")
  const items = $derived(contextMenuItems(kind, operations))

  const choose = (id: string) => {
    selected = id
  }

  const close = () => {
    selected = "Closed"
  }
</script>

<div style="position: relative; min-height: 340px">
  <CanvasContextMenu {label} menuItems={items} x={16} y={16} onaction={choose} onclose={close} />
</div>
<output aria-live="polite">{selected}</output>
