import type { StorybookConfig } from "@storybook/svelte-vite"

const base = process.env.WOTEX_LAB_STORYBOOK_BASE ?? "/"

if (!/^\/(?:[a-zA-Z0-9._~-]+\/)*$/.test(base)) {
  throw new Error("WOTEX_LAB_STORYBOOK_BASE must be an absolute path ending in /")
}

const config: StorybookConfig = {
  stories: ["../assets/**/*.stories.ts"],
  addons: ["@storybook/addon-a11y"],
  framework: { name: "@storybook/svelte-vite", options: { docgen: false } },
  core: { disableTelemetry: true },
  viteFinal: async (viteConfig) => ({ ...viteConfig, base }),
}

export default config
