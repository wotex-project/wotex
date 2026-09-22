import type { Preview } from "@storybook/svelte-vite"
import "../assets/components/design-system.css"
import "../assets/islands/design-system.css"

document.documentElement.setAttribute("data-wotex-design-system", "")
document.documentElement.setAttribute("data-wotex-theme", "light")

const preview: Preview = {
  parameters: {
    a11y: { test: "error" },
    backgrounds: { disable: true },
    controls: { expanded: true },
    layout: "padded",
  },
}

export default preview
