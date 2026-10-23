import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import RadioGroup from "$lib/primitives/radio-group/radio-group.svelte"

const meta: Meta = {
  id: "forms-radio-group",
  title: "Forms/Radio group",
  component: RadioGroup,
  parameters: {
    fixture: storyFixture("radio-group"),
  },
}
export default meta

type Story = StoryObj

export const Default: Story = {
  args: componentStory("radio-group", "Default"),
}
