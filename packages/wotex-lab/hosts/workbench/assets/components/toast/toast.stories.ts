import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Toast from "$lib/components/toast/toast.svelte"

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
