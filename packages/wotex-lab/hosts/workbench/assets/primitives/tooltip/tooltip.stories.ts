import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Tooltip from "$lib/catalogue/tooltip-example/tooltip-example.svelte"

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
