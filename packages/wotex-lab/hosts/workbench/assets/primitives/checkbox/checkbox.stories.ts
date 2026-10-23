import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Checkbox from "$lib/primitives/checkbox/checkbox.svelte"

const meta: Meta = {
  id: "forms-checkbox",
  title: "Forms/Checkbox",
  component: Checkbox,
  parameters: {
    fixture: storyFixture("checkbox"),
  },
}
export default meta

type Story = StoryObj

export const Checked: Story = {
  args: componentStory("checkbox", "Checked"),
}
