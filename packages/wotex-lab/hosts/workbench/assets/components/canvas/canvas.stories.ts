import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport, islandStory } from "$lib/catalogue/index.ts"
import Canvas from "$lib/islands/canvas/canvas.svelte"

const meta: Meta = { title: "Components/Canvas", component: Canvas }
export default meta

type Story = StoryObj
export const Connected: Story = {
  args: { payload: islandStory("canvas"), transport: createStoryTransport() },
}
export const WithPins: Story = {
  args: { payload: islandStory("canvas", "with_pins"), transport: createStoryTransport() },
}
