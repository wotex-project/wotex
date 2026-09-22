import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Legend from "./legend.svelte"

const meta: Meta = {
  id: "reporting-legend",
  title: "Reporting/Legend",
  component: Legend,
  parameters: { fixture: storyFixture("legend") },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: { label: "Series", items: [{ id: "requests", label: "Requests", color: "#3457d5" }] },
}
export const Empty: Story = { args: { label: "Series", items: [] } }
