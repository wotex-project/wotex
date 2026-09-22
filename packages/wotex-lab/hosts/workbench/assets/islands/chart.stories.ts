import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport } from "../catalogue/index.js"
import Chart from "./chart.svelte"

const meta: Meta = { title: "Lab islands/Chart", component: Chart }
export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: {
      title: "Room temperature",
      series: [{ id: "temperature", label: "Temperature °C" }],
      points: [
        { key: "one", label: "09:00", values: { temperature: 20.4 } },
        { key: "two", label: "10:00", values: { temperature: 21.1 } },
        { key: "three", label: "11:00", values: { temperature: 20.8 } },
      ],
    },
    transport: createStoryTransport(),
  },
}

export const Empty: Story = {
  args: {
    payload: { title: "Room temperature", series: [], points: [] },
    transport: createStoryTransport(),
  },
}
