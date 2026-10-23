import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory } from "$lib/catalogue/index.ts"
import Input from "$lib/primitives/input/input.svelte"

const meta: Meta = {
  id: "primitives-input",
  title: "Primitives/Input",
  component: Input,
}

export default meta

type Story = StoryObj

export const Default: Story = {
  args: componentStory("input", "Default"),
}

export const Disabled: Story = {
  args: componentStory("input", "Disabled"),
}
