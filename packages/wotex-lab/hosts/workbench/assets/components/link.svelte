<script lang="ts">
import type { Snippet } from "svelte"

const safeHref = (value: string) => {
  if ((value.startsWith("/") && !value.startsWith("//")) || value.startsWith("#")) return value
  const url = new URL(value)
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
    throw new Error("design-system link requires a safe HTTP(S), root-relative, or fragment URL")
  }
  return value
}

let { href, label, children }: { href: string; label: string; children?: Snippet } = $props()
const admittedHref = $derived(safeHref(href))
</script>

<a href={admittedHref}>{#if children}{@render children()}{:else}{label}{/if}</a>
