import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import DataGrid from "./data-grid.svelte"

const meta: Meta = {
  id: "data-grid",
  title: "Data grid",
  component: DataGrid,
  parameters: {
    fixture: storyFixture("data-grid"),
  },
}
export default meta
type Story = StoryObj
export const Populated: Story = {
  args: componentStory("data-grid", "Populated"),
}
export const Empty: Story = {
  args: componentStory("data-grid", "Empty"),
}
