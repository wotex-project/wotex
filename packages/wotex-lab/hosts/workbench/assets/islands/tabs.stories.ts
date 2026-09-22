import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport } from "../catalogue/index.js"
import Tabs from "./tabs.svelte"

const meta: Meta = { title: "Lab islands/Tabs", component: Tabs }
export default meta
type Story = StoryObj

export const Connected: Story = {
  args: {
    payload: {
      label: "Run evidence",
      selected: "metrics",
      tabs: [
        { id: "metrics", label: "Metrics", content: "Bounded measurements" },
        { id: "logs", label: "Logs", content: "Structured runtime events" },
        { id: "traces", label: "Traces", content: "Causal operation spans" },
      ],
    },
    transport: createStoryTransport(),
  },
}
