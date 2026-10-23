import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { createStoryTransport } from "../catalogue/index.js"
import Canvas from "./canvas.svelte"

const meta: Meta = {
  title: "Lab islands/Connected Things",
  component: Canvas,
}

export default meta
type Story = StoryObj

const payload = {
  label: "Connected Things",
  nodes: [
    {
      id: "thing-thermostat",
      kind: "thing",
      title: "Thermostat",
      identity: "urn:test:thermostat",
      value: "21.5",
      unit: "°C",
      status: "Read",
      detail: "Explicit read · fixture",
      x: 160,
      y: 235,
    },
    {
      id: "process-smart-room",
      kind: "process",
      title: "Smart room",
      identity: "smart_room",
      value: "",
      unit: "",
      status: "Idle",
      detail: "Observe and propose",
      x: 520,
      y: 365,
    },
  ],
  edges: [
    {
      id: "temperature",
      source: "thing-thermostat",
      target: "process-smart-room",
      label: "temperature · °C",
      kind: "input",
      target_handle: "temperature",
    },
  ],
}

export const Connected: Story = {
  args: {
    payload,
    transport: createStoryTransport({
      inspect: {
        status: "accepted",
      },
      open: {
        status: "accepted",
      },
    }),
  },
}

export const Empty: Story = {
  args: {
    payload: {
      label: "Connected Things",
      nodes: [],
      edges: [],
    },
    transport: createStoryTransport(),
  },
}

const disconnected = createStoryTransport()
disconnected.disconnect()

export const Disconnected: Story = {
  args: {
    payload,
    transport: disconnected,
  },
}
