import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Inspector from "./inspector.svelte"

const meta: Meta = {
  id: "reporting-inspector",
  title: "Reporting/Inspector",
  component: Inspector,
  parameters: {
    fixture: storyFixture("inspector"),
  },
}
export default meta
type Story = StoryObj
export const Open: Story = {
  args: componentStory("inspector", "Open"),
}
