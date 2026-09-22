import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Toast from "./toast.svelte"

const meta: Meta = {
  id: "feedback-toast",
  title: "Feedback/Toast",
  component: Toast,
  parameters: { fixture: storyFixture("toast") },
}
export default meta
type Story = StoryObj
export const Success: Story = { args: { message: "Changes saved", kind: "success" } }
export const Error: Story = { args: { message: "Changes were not saved", kind: "danger" } }
