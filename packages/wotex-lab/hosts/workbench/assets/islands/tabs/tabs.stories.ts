import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport, islandStory } from "$lib/catalogue/index.ts"
import Tabs from "$lib/islands/tabs/tabs.svelte"

const meta: Meta = {
  title: "Lab islands/Tabs",
  component: Tabs,
}

export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: islandStory("tabs"),
    transport: createStoryTransport(),
  },
}
