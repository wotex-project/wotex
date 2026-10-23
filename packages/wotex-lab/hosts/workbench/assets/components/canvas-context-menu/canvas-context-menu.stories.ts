import type { Meta, StoryObj } from "@storybook/svelte-vite"
import ContextMenuExample from "$lib/catalogue/canvas-context-menu-example/canvas-context-menu-example.svelte"
import { componentStory } from "$lib/catalogue/index.ts"

const meta: Meta = { title: "Components/Canvas context menu", component: ContextMenuExample }
export default meta

type Story = StoryObj

export const Thing: Story = { args: componentStory("canvas-context-menu", "Thing") }
export const Connection: Story = { args: componentStory("canvas-context-menu", "Connection") }
export const Metric: Story = { args: componentStory("canvas-context-menu", "Metric") }
export const Run: Story = { args: componentStory("canvas-context-menu", "Run") }
