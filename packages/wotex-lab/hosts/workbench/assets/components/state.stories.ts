import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import State from "./state.svelte"

const meta: Meta = {
  id: "feedback-state",
  title: "Feedback/State",
  component: State,
  parameters: { fixture: storyFixture("state") },
}
export default meta
type Story = StoryObj
export const Disconnected: Story = {
  args: { title: "Disconnected", message: "Reconnect to resume.", state: "disconnected" },
}
export const Error: Story = {
  args: {
    title: "Could not load",
    message: "The last valid content remains available.",
    state: "error",
  },
}
