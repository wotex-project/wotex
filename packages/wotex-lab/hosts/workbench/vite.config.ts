import { resolve } from "node:path"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import { defineConfig } from "vite"

export default defineConfig({
  resolve: {
    alias: {
      $lib: resolve(import.meta.dirname, "assets"),
      $seeds: resolve(import.meta.dirname, "priv/seeds"),
    },
  },
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
        documentation: resolve(import.meta.dirname, "assets/documentation.ts"),
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
