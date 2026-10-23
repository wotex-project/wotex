import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import DataTable from "$lib/components/data-table/data-table.svelte"

const meta: Meta = {
  id: "data-table",
  title: "Data/Table",
  component: DataTable,
  parameters: {
    fixture: storyFixture("table"),
  },
}
export default meta

type Story = StoryObj

export const Populated: Story = {
  args: componentStory("data-table", "Populated"),
}
export const Empty: Story = {
  args: componentStory("data-table", "Empty"),
}
