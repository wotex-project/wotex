import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Filter from "./filter.svelte"

const meta: Meta = {
  id: "reporting-filter",
  title: "Reporting/Filter",
  component: Filter,
  parameters: { fixture: storyFixture("filter") },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: {
    legend: "Filter results",
    fields: [
      { name: "query", label: "Contains" },
      {
        name: "state",
        label: "State",
        options: [
          { label: "Any", value: "" },
          { label: "Ready", value: "ready" },
        ],
      },
    ],
  },
}
