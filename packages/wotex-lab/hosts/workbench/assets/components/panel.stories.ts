import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Panel from "./panel.svelte"

const meta: Meta = {
  id: "layout-panel",
  title: "Layout/Panel",
  component: Panel,
  parameters: { fixture: storyFixture("panel") },
}
export default meta
type Story = StoryObj
export const Default: Story = { args: { title: "Summary" } }
