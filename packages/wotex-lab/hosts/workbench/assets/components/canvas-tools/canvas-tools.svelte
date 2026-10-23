<script lang="ts">
  import metrics from "$lib/components/canvas/assets/chart-no-axes-combined.svg"
  import experiments from "$lib/components/canvas/assets/flask-conical.svg"
  import hand from "$lib/components/canvas/assets/hand.svg"
  import fit from "$lib/components/canvas/assets/maximize.svg"
  import pointer from "$lib/components/canvas/assets/mouse-pointer-2.svg"
  import plus from "$lib/components/canvas/assets/plus.svg"
  import save from "$lib/components/canvas/assets/save.svg"
  import connectionsIcon from "$lib/components/canvas/assets/waypoints.svg"
  import Button from "$lib/primitives/button/button.svelte"

  export type CanvasTool =
    | "select"
    | "pan"
    | "add"
    | "connections"
    | "metrics"
    | "experiments"
    | "save"
    | "fit"

  let {
    pan = false,
    connected = true,
    saving = false,
    saved = false,
    onselect,
  }: {
    pan?: boolean
    connected?: boolean
    saving?: boolean
    saved?: boolean
    onselect: (tool: CanvasTool) => void
  } = $props()

  const tools = $derived([
    { id: "select", label: "Select", image: pointer, pressed: !pan, disabled: false },
    { id: "pan", label: "Pan", image: hand, pressed: pan, disabled: false },
    { id: "add", label: "Add Thing", image: plus, disabled: !connected },
    { id: "connections", label: "Connections", image: connectionsIcon, disabled: !connected },
    { id: "metrics", label: "Metrics", image: metrics, disabled: !connected },
    { id: "experiments", label: "Experiments", image: experiments, disabled: !connected },
    { id: "save", label: "Save layout", image: save, disabled: !connected || saving },
    { id: "fit", label: "Fit connected Things", image: fit, disabled: false },
  ])

  const selectTool = (id: string) => onselect(id as CanvasTool)

  const selectItem = (id: string) => () => selectTool(id)
</script>

<nav class="wl-canvas-tools" aria-label="Canvas tools">
  {#each tools as tool (tool.id)}
    <Button
      unstyled
      type="button"
      aria-label={tool.label}
      aria-pressed={tool.pressed}
      title={tool.id === "save" && saved ? "Layout saved" : tool.label}
      disabled={tool.disabled}
      onclick={selectItem(tool.id)}
    >
      <img src={tool.image} alt="">
    </Button>
  {/each}
</nav>
