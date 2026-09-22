import "./islands/design-system.css"
import { WotexLabSvelteIsland } from "./islands/hook.js"

interface StorybookRegistry {
  Hooks?: Record<string, unknown>
  LiveSocketOptions?: Record<string, unknown>
  Params?: Record<string, unknown>
  Phoenix?: unknown
  LiveView?: unknown
  Uploaders?: Record<string, unknown>
}

declare global {
  interface Window {
    storybook?: StorybookRegistry
  }
}

const storybook = window.storybook ?? {}

window.storybook = {
  ...storybook,
  Hooks: {
    ...storybook.Hooks,
    WotexLabSvelteIsland,
  },
}
