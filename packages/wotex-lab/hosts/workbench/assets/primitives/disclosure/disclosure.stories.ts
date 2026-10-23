import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Disclosure from "$lib/primitives/disclosure/disclosure.svelte"

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
