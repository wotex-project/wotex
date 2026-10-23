import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Link from "$lib/primitives/link/link.svelte"

const meta: Meta = {
  id: "primitives-link",
  title: "Primitives/Link",
  component: Link,
  parameters: {
    fixture: storyFixture("link"),
  },
}
export default meta
type Story = StoryObj
export const Internal: Story = {
  args: componentStory("link", "Internal"),
}
export const External: Story = {
  args: componentStory("link", "External"),
}
