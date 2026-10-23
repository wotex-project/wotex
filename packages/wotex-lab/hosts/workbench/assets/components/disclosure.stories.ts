import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Disclosure from "./disclosure.svelte"

const meta: Meta = {
  id: "navigation-disclosure",
  title: "Navigation/Disclosure",
  component: Disclosure,
  parameters: {
    fixture: storyFixture("disclosure"),
  },
}
export default meta
type Story = StoryObj
export const Open: Story = {
  args: componentStory("disclosure", "Open"),
}
