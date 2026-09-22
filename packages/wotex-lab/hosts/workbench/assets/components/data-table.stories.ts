import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import DataTable from "./data-table.svelte"

const meta: Meta = {
  id: "data-table",
  title: "Data/Table",
  component: DataTable,
  parameters: { fixture: storyFixture("table") },
}
export default meta
type Story = StoryObj
export const Populated: Story = {
  args: {
    caption: "Example records",
    columns: [
      { key: "name", label: "Name" },
      { key: "state", label: "State" },
    ],
    rows: [{ key: "one", values: { name: "First", state: "Ready" } }],
  },
}
export const Empty: Story = { args: { caption: "Example records", columns: [], rows: [] } }
