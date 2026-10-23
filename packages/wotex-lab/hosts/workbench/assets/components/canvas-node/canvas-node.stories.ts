import type { Meta, StoryObj } from "@storybook/svelte-vite"
import NodeExample from "$lib/catalogue/canvas-node-example/canvas-node-example.svelte"
import { componentStory } from "$lib/catalogue/index.ts"

const meta: Meta = { title: "Components/canvas-node", component: NodeExample }
export default meta

type Story = StoryObj
export const Thing: Story = {
  args: { kind: "thing", payload: componentStory("canvas-node", "Thing") },
}
export const Process: Story = {
  args: { kind: "thing", payload: componentStory("canvas-node", "Process") },
}
