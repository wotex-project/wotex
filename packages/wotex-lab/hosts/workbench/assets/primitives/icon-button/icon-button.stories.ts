import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import IconButton from "$lib/primitives/icon-button/icon-button.svelte"

const meta: Meta = {
  id: "primitives-icon-button",
  title: "Primitives/Icon button",
  component: IconButton,
  parameters: {
    fixture: storyFixture("icon-button"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("icon-button", "Default"),
}
export const Disabled: Story = {
  args: componentStory("icon-button", "Disabled"),
}
