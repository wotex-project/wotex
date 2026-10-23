import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Legend from "$lib/components/legend/legend.svelte"

const meta: Meta = {
  id: "reporting-legend",
  title: "Reporting/Legend",
  component: Legend,
  parameters: {
    fixture: storyFixture("legend"),
  },
}
export default meta

type Story = StoryObj

export const Default: Story = {
  args: componentStory("legend", "Default"),
}
export const Empty: Story = {
  args: componentStory("legend", "Empty"),
}
