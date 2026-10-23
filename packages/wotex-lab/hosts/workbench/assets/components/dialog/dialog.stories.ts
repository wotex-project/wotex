import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "$lib/catalogue/index.ts"
import Dialog from "$lib/components/dialog/dialog.svelte"

const meta: Meta = {
  id: "overlays-dialog",
  title: "Overlays/Dialog",
  component: Dialog,
  parameters: {
    fixture: storyFixture("dialog"),
  },
}
export default meta

type Story = StoryObj

export const Open: Story = {
  args: componentStory("dialog", "Open"),
}
