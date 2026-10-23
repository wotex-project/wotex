import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Filter from "./filter.svelte"

const meta: Meta = {
  id: "reporting-filter",
  title: "Reporting/Filter",
  component: Filter,
  parameters: {
    fixture: storyFixture("filter"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("filter", "Default"),
}
