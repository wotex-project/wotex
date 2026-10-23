import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Navigation from "$lib/components/navigation/navigation.svelte"

const meta: Meta = {
  id: "navigation-list",
  title: "Navigation/List",
  component: Navigation,
  parameters: {
    fixture: storyFixture("navigation"),
  },
}
export default meta
type Story = StoryObj
export const CurrentPage: Story = {
  args: componentStory("navigation", "CurrentPage"),
}
