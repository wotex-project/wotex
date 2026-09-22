import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Progress from "./progress.svelte"

const meta: Meta = {
  id: "feedback-progress",
  title: "Feedback/Progress",
  component: Progress,
  parameters: { fixture: storyFixture("progress") },
}
export default meta
type Story = StoryObj
export const Determinate: Story = { args: { label: "Upload progress", value: 64 } }
export const Indeterminate: Story = { args: { label: "Working" } }
