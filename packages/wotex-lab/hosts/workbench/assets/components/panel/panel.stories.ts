import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Panel from "$lib/components/panel/panel.svelte"

const meta: Meta = {
  id: "layout-panel",
  title: "Layout/Panel",
  component: Panel,
  parameters: {
    fixture: storyFixture("panel"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("panel", "Default"),
}
