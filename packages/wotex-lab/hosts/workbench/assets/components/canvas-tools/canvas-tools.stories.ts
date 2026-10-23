import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory } from "$lib/catalogue/index.ts"
import CanvasTools from "$lib/components/canvas-tools/canvas-tools.svelte"
import "$lib/components/canvas/canvas.css"

const meta: Meta = {
  title: "Components/Canvas tools",
  component: CanvasTools,
  args: { onselect: () => undefined },
}
export default meta

type Story = StoryObj

export const Connected: Story = { args: componentStory("canvas-tools", "Connected") }
export const Disconnected: Story = { args: componentStory("canvas-tools", "Disconnected") }
export const Saving: Story = { args: componentStory("canvas-tools", "Saving") }
export const Saved: Story = { args: componentStory("canvas-tools", "Saved") }
export const Pan: Story = { args: componentStory("canvas-tools", "Pan") }
