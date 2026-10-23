import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Menu from "./menu.svelte"

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
