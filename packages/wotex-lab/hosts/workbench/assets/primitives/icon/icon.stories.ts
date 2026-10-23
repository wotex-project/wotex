import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory } from "$lib/catalogue/index.ts"
import Icon from "$lib/primitives/icon/icon.svelte"

const meta: Meta = { title: "Primitives/Icon", component: Icon }
export default meta

type Story = StoryObj
export const Default: Story = { args: componentStory("icon", "Default") }
