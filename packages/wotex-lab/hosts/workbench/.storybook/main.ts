import { resolve } from "node:path"
import type { StorybookConfig } from "@storybook/svelte-vite"
import { mergeConfig } from "vite"

const base = process.env.WOTEX_LAB_STORYBOOK_BASE ?? "/"

if (!/^\/(?:[a-zA-Z0-9._~-]+\/)*$/.test(base)) {
  throw new Error("WOTEX_LAB_STORYBOOK_BASE must be an absolute path ending in /")
}

const config: StorybookConfig = {
  stories: ["../assets/**/*.stories.ts"],
  addons: ["@storybook/addon-a11y"],
  framework: {
    name: "@storybook/svelte-vite",
    options: {
      docgen: false,
    },
  },
  core: {
    disableTelemetry: true,
  },

  viteFinal: async (viteConfig) =>
    mergeConfig(viteConfig, {
      base,
      resolve: {
        alias: {
          $lib: resolve(import.meta.dirname, "../assets"),
          $seeds: resolve(import.meta.dirname, "../priv/seeds"),
        },
      },
    }),
}

export default config
