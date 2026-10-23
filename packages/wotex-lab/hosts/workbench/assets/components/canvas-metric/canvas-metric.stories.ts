import type { Meta, StoryObj } from "@storybook/svelte-vite"
import NodeExample from "$lib/catalogue/canvas-node-example/canvas-node-example.svelte"
import { componentStory } from "$lib/catalogue/index.ts"

const meta: Meta = { title: "Components/canvas-metric", component: NodeExample }
export default meta

type Story = StoryObj
export const Paused: Story = {
  args: { kind: "metric", payload: componentStory("canvas-metric", "Paused") },
}
