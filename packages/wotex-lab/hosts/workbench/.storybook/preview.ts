import type { Preview } from "@storybook/svelte-vite"
import "$lib/design-system/design-system.css"
import "$lib/islands/design-system.css"

document.documentElement.setAttribute("data-wotex-design-system", "")
document.documentElement.setAttribute("data-wotex-theme", "light")

const preview: Preview = {
  parameters: {
    a11y: {
      test: "error",
    },
    backgrounds: {
      disable: true,
    },
    controls: {
      expanded: true,
    },
    layout: "padded",
  },
}

export default preview
