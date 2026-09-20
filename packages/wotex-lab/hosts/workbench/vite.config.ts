import { resolve } from "node:path"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import { defineConfig } from "vite"

const candidate = process.env.PHOENIX_ASSETS_SVELTE_CANDIDATE

export default defineConfig({
  base: "/",
  plugins: [svelte()],
  resolve: candidate
    ? {
        alias: [
          {
            find: "@phoenix-assets/svelte/islands",
            replacement: resolve(candidate, "islands/index.js"),
          },
          {
            find: "@phoenix-assets/svelte/design-system.css",
            replacement: resolve(candidate, "design-system/design-system.css"),
          },
        ],
      }
    : undefined,
  build: {
    assetsDir: "assets",
    emptyOutDir: false,
    manifest: true,
    outDir: resolve(import.meta.dirname, "priv/static"),
    rollupOptions: {
      input: {
        app: resolve(import.meta.dirname, "assets/app.ts"),
        storybook: resolve(import.meta.dirname, "assets/storybook.ts"),
      },
      output: {
        chunkFileNames: "assets/island-[name]-[hash].js",
        entryFileNames: "assets/workbench-[hash].js",
        assetFileNames: "assets/workbench-[hash][extname]",
      },
    },
    sourcemap: false,
  },
})
