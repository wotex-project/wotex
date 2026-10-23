import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Menu from "$lib/catalogue/menu-example/menu-example.svelte"

const meta: Meta = {
  id: "overlays-menu",
  title: "Overlays/Menu",
  component: Menu,
  parameters: {
    fixture: storyFixture("menu"),
  },
}
export default meta
type Story = StoryObj
export const Open: Story = {
  args: componentStory("menu", "Open"),
}

export const DisabledItems: Story = { args: componentStory("menu", "DisabledItems") }
