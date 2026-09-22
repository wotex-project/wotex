import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Tooltip from "./tooltip.svelte"

const meta: Meta = {
  id: "overlays-tooltip",
  title: "Overlays/Tooltip",
  component: Tooltip,
  parameters: { fixture: storyFixture("tooltip") },
}
export default meta
type Story = StoryObj
export const Default: Story = { args: { text: "Additional context" } }
