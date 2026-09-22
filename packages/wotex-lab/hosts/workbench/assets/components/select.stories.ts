import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Select from "./select.svelte"

const meta: Meta = {
  id: "forms-select",
  title: "Forms/Select",
  component: Select,
  parameters: { fixture: storyFixture("select") },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: {
    id: "region",
    name: "region",
    label: "Region",
    value: "eu",
    options: [
      { label: "Europe", value: "eu" },
      { label: "Americas", value: "us" },
    ],
  },
}
