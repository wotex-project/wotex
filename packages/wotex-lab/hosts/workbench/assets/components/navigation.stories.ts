import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Navigation from "./navigation.svelte"

const meta: Meta = {
  id: "navigation-list",
  title: "Navigation/List",
  component: Navigation,
  parameters: { fixture: storyFixture("navigation") },
}
export default meta
type Story = StoryObj
export const CurrentPage: Story = {
  args: {
    label: "Documentation",
    current: "/guide",
    items: [
      { id: "home", title: "Home", path: "/" },
      { id: "guide", title: "Guide", path: "/guide" },
    ],
  },
}
