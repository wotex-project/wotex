import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import DataGrid from "./data-grid.svelte"

const meta: Meta = {
  id: "data-grid",
  title: "Data grid",
  component: DataGrid,
  parameters: { fixture: storyFixture("data-grid") },
}
export default meta
type Story = StoryObj
export const Populated: Story = {
  args: {
    label: "Records",
    columns: [
      { key: "name", label: "Name" },
      { key: "state", label: "State" },
    ],
    rows: [
      { key: "one", values: { name: "First", state: "Ready" } },
      { key: "two", values: { name: "Second", state: "Waiting" } },
    ],
  },
}
export const Empty: Story = { args: { label: "Records", columns: [], rows: [] } }
