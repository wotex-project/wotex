import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Chart from "./chart.svelte"

const meta: Meta = {
  id: "reporting-chart",
  title: "Reporting/Chart",
  component: Chart,
  parameters: { fixture: storyFixture("chart") },
}
export default meta
type Story = StoryObj
export const Populated: Story = {
  args: {
    title: "Throughput",
    series: [{ id: "requests", label: "Requests" }],
    points: [
      { key: "one", label: "09:00", values: { requests: 20 } },
      { key: "two", label: "10:00", values: { requests: 48 } },
    ],
  },
}
export const Empty: Story = { args: { title: "Throughput", series: [], points: [] } }
