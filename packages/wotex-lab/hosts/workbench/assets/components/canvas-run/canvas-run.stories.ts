import type { Meta, StoryObj } from "@storybook/svelte-vite"
import NodeExample from "$lib/catalogue/canvas-node-example/canvas-node-example.svelte"
import { componentStory } from "$lib/catalogue/index.ts"

const meta: Meta = { title: "Components/canvas-run", component: NodeExample }
export default meta

type Story = StoryObj
export const Captured: Story = {
  args: { kind: "run_result", payload: componentStory("canvas-run", "Captured") },
}
export const Unavailable: Story = {
  args: { kind: "run_result", payload: componentStory("canvas-run", "Unavailable") },
}
