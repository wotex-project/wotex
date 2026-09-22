import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import RadioGroup from "./radio-group.svelte"

const meta: Meta = {
  id: "forms-radio-group",
  title: "Forms/Radio group",
  component: RadioGroup,
  parameters: { fixture: storyFixture("radio-group") },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: {
    name: "density",
    legend: "Density",
    value: "comfortable",
    options: [
      { label: "Comfortable", value: "comfortable" },
      { label: "Compact", value: "compact" },
    ],
  },
}
