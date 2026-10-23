import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import StatusBadge from "./status-badge.svelte"

const meta: Meta = {
  id: "feedback-status-badge",
  title: "Feedback/Status badge",
  component: StatusBadge,
  parameters: {
    fixture: storyFixture("status-badge"),
  },
}
export default meta
type Story = StoryObj
export const Success: Story = {
  args: componentStory("status-badge", "Success"),
}
export const Danger: Story = {
  args: componentStory("status-badge", "Danger"),
}
