import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport } from "../catalogue/index.js"
import DataGrid from "./data-grid.svelte"

const meta: Meta = { title: "Lab islands/Data grid", component: DataGrid }
export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: {
      label: "Discovered Things",
      columns: [
        { key: "name", label: "Thing" },
        { key: "protocol", label: "Protocol" },
      ],
      rows: [
        { key: "sensor", values: { name: "Lab sensor", protocol: "CoAP" } },
        { key: "relay", values: { name: "Bench relay", protocol: "Modbus" } },
      ],
    },
    transport: createStoryTransport(),
  },
}

export const Empty: Story = {
  args: {
    payload: { label: "Discovered Things", columns: [], rows: [] },
    transport: createStoryTransport(),
  },
}
