import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Button from "./button.svelte"

const meta: Meta = {
  id: "primitives-button",
  title: "Primitives/Button",
  component: Button,
  parameters: {
    fixture: storyFixture("button"),
  },
}
export default meta
type Story = StoryObj
export const Primary: Story = {
  args: componentStory("button", "Primary"),
}
export const Loading: Story = {
  args: componentStory("button", "Loading"),
}
export const Disabled: Story = {
  args: componentStory("button", "Disabled"),
}
export const Danger: Story = {
  args: componentStory("button", "Danger"),
}
