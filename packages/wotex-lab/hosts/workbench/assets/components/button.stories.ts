import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { storyFixture } from "../catalogue/index.js"
import Button from "./button.svelte"

const meta: Meta = {
  id: "primitives-button",
  title: "Primitives/Button",
  component: Button,
  parameters: { fixture: storyFixture("button") },
}
export default meta
type Story = StoryObj
export const Primary: Story = { args: { label: "Primary action" } }
export const Loading: Story = { args: { label: "Loading", loading: true } }
export const Disabled: Story = { args: { label: "Unavailable", disabled: true } }
export const Danger: Story = { args: { label: "Delete", variant: "danger" } }
