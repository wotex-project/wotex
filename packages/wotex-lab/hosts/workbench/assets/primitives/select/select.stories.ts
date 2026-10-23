import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Select from "$lib/primitives/select/select.svelte"

const meta: Meta = {
  id: "forms-select",
  title: "Forms/Select",
  component: Select,
  parameters: {
    fixture: storyFixture("select"),
  },
}
export default meta

type Story = StoryObj

export const Default: Story = {
  args: componentStory("select", "Default"),
}
