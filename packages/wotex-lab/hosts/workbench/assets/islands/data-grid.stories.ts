import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport, islandStory } from "../catalogue/index.js"
import DataGrid from "./data-grid.svelte"

const meta: Meta = {
  title: "Lab islands/Data grid",
  component: DataGrid,
}

export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: islandStory("data-grid"),
    transport: createStoryTransport(),
  },
}

export const Empty: Story = {
  args: {
    payload: islandStory("data-grid", "empty"),
    transport: createStoryTransport(),
  },
}
