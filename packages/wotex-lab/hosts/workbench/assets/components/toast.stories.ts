import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Toast from "./toast.svelte"

const meta: Meta = {
  id: "feedback-toast",
  title: "Feedback/Toast",
  component: Toast,
  parameters: {
    fixture: storyFixture("toast"),
  },
}
export default meta
type Story = StoryObj
export const Success: Story = {
  args: componentStory("toast", "Success"),
}
const ErrorState: Story = {
  args: {
    message: "Changes were not saved",
    kind: "danger",
  },
}

export { ErrorState as Error }
