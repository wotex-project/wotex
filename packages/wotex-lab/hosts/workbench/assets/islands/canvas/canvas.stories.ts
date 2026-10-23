import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport, islandStory } from "$lib/catalogue/index.ts"
import Canvas from "$lib/islands/canvas/canvas.svelte"

const meta: Meta = {
  title: "Lab islands/Connected Things",
  component: Canvas,
}

export default meta

type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: islandStory("canvas"),
    transport: createStoryTransport(),
  },
}

export const Empty: Story = {
  args: {
    payload: islandStory("canvas", "empty"),
    transport: createStoryTransport(),
  },
}

const disconnected = createStoryTransport()
disconnected.disconnect()

export const Disconnected: Story = {
  args: {
    payload: islandStory("canvas"),
    transport: disconnected,
  },
}
