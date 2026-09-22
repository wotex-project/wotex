import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Field from "./field.svelte"

const meta: Meta = {
  id: "forms-field",
  title: "Forms/Field",
  component: Field,
  parameters: { fixture: storyFixture("field") },
}
export default meta
type Story = StoryObj
export const Default: Story = { args: { id: "name", name: "name", label: "Name" } }
export const Invalid: Story = {
  args: {
    id: "email",
    name: "email",
    label: "Email",
    value: "invalid",
    error: "Enter a valid address",
  },
}
