import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Tooltip from "../catalogue/tooltip-example.svelte"

const meta: Meta = {
  id: "overlays-tooltip",
  title: "Overlays/Tooltip",
  component: Tooltip,
  parameters: {
    fixture: storyFixture("tooltip"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("tooltip", "Default"),
}
