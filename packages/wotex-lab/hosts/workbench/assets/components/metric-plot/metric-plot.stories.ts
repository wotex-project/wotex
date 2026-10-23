import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory } from "$lib/catalogue/index.ts"
import MetricPlot from "$lib/components/metric-plot/metric-plot.svelte"
import "$lib/components/canvas/canvas.css"

const meta: Meta = { title: "Components/Metric plot", component: MetricPlot }
export default meta

type Story = StoryObj

export const Default: Story = { args: componentStory("metric-plot", "Default") }
export const Empty: Story = { args: componentStory("metric-plot", "Empty") }
