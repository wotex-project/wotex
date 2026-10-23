import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import State from "./state.svelte"

const meta: Meta = {
  id: "feedback-state",
  title: "Feedback/State",
  component: State,
  parameters: {
    fixture: storyFixture("state"),
  },
}
export default meta
type Story = StoryObj
export const Disconnected: Story = {
  args: componentStory("state", "Disconnected"),
}
const ErrorState: Story = {
  args: {
    title: "Could not load",
    message: "The last valid content remains available.",
    state: "error",
  },
}

export { ErrorState as Error }
