import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Link from "./link.svelte"

const meta: Meta = {
  id: "primitives-link",
  title: "Primitives/Link",
  component: Link,
  parameters: { fixture: storyFixture("link") },
}
export default meta
type Story = StoryObj
export const Internal: Story = { args: { href: "/guide", label: "Read the guide" } }
export const External: Story = {
  args: { href: "https://example.test/docs", label: "External documentation" },
}
