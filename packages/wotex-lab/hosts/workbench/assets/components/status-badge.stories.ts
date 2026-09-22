import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import StatusBadge from "./status-badge.svelte"

const meta: Meta = {
  id: "feedback-status-badge",
  title: "Feedback/Status badge",
  component: StatusBadge,
  parameters: { fixture: storyFixture("status-badge") },
}
export default meta
type Story = StoryObj
export const Success: Story = { args: { label: "Ready", kind: "success" } }
export const Danger: Story = { args: { label: "Failed", kind: "danger" } }
