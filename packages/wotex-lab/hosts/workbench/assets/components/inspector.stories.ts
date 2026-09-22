import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Inspector from "./inspector.svelte"

const meta: Meta = {
  id: "reporting-inspector",
  title: "Reporting/Inspector",
  component: Inspector,
  parameters: { fixture: storyFixture("inspector") },
}
export default meta
type Story = StoryObj
export const Open: Story = {
  args: {
    title: "Record details",
    open: true,
    fields: [
      { label: "State", value: "Ready" },
      { label: "Owner", value: "Example" },
    ],
  },
}
