import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Callout from "$lib/components/callout/callout.svelte"

const meta: Meta = {
  id: "feedback-callout",
  title: "Feedback/Callout",
  component: Callout,
  parameters: {
    fixture: storyFixture("callout"),
  },
}
export default meta
type Story = StoryObj
export const Note: Story = {
  args: componentStory("callout", "Note"),
}
export const Warning: Story = {
  args: componentStory("callout", "Warning"),
}
