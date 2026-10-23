import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Chart from "$lib/components/chart/chart.svelte"

const meta: Meta = {
  id: "reporting-chart",
  title: "Reporting/Chart",
  component: Chart,
  parameters: {
    fixture: storyFixture("chart"),
  },
}
export default meta

type Story = StoryObj

export const Populated: Story = {
  args: componentStory("chart", "Populated"),
}
export const Empty: Story = {
  args: componentStory("chart", "Empty"),
}
