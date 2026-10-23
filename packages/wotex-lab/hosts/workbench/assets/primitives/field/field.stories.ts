import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Field from "$lib/primitives/field/field.svelte"

const meta: Meta = {
  id: "forms-field",
  title: "Forms/Field",
  component: Field,
  parameters: {
    fixture: storyFixture("field"),
  },
}
export default meta
type Story = StoryObj
export const Default: Story = {
  args: componentStory("field", "Default"),
}
export const Invalid: Story = {
  args: componentStory("field", "Invalid"),
}
