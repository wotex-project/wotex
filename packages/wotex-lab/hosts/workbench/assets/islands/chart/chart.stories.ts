import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport, islandStory } from "$lib/catalogue/index.ts"
import Chart from "$lib/islands/chart/chart.svelte"

const meta: Meta = {
  title: "Lab islands/Chart",
  component: Chart,
}

export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: islandStory("chart"),
    transport: createStoryTransport(),
  },
}

export const Empty: Story = {
  args: {
    payload: islandStory("chart", "empty"),
    transport: createStoryTransport(),
  },
}
