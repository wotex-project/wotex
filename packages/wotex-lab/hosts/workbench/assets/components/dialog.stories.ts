import type { Meta, StoryObj } from "@storybook/svelte-vite"
import { componentStory, storyFixture } from "../catalogue/index.js"
import Dialog from "./dialog.svelte"

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
