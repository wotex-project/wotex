import { resolve } from "node:path"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import { defineConfig } from "vite"

export default defineConfig({
  base: "/",
  plugins: [svelte()],
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
