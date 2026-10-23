import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Progress from "$lib/primitives/progress/progress.svelte"

const meta: Meta = {
  id: "feedback-progress",
  title: "Feedback/Progress",
  component: Progress,
  parameters: {
    fixture: storyFixture("progress"),
  },
}
export default meta
type Story = StoryObj
export const Determinate: Story = {
  args: componentStory("progress", "Determinate"),
}
export const Indeterminate: Story = {
  args: componentStory("progress", "Indeterminate"),
}
