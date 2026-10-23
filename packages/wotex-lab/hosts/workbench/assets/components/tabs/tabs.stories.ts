import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Tabs from "$lib/components/tabs/tabs.svelte"

const meta: Meta = {
  id: "navigation-tabs",
  title: "Navigation/Tabs",
  component: Tabs,
  parameters: {
    fixture: storyFixture("tabs"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("tabs", "Default"),
}
