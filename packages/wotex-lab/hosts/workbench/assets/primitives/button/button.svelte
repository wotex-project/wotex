<script lang="ts">
  import type { Snippet } from "svelte"
  import type { HTMLButtonAttributes } from "svelte/elements"

  let {
    label = "",
    variant = "primary",
    disabled = false,
    loading = false,
    unstyled = false,
    children,
    class: className,
    type = "button",
    ...attributes
  }: Omit<HTMLButtonAttributes, "children"> & {
    label?: string
    variant?: "primary" | "secondary" | "danger"
    loading?: boolean
    unstyled?: boolean
    children?: Snippet
  } = $props()

  const classes = $derived(
    unstyled ? className : ["wl-button", className].filter(Boolean).join(" "),
  )
</script>

<button
  {...attributes}
  {type}
  class={classes}
  data-wotex-variant={unstyled ? attributes["data-wotex-variant"] : variant}
  {disabled}
  aria-busy={loading || attributes["aria-busy"] || undefined}
>
  {#if children}
    {@render children()}
  {:else}
    {label}
  {/if}
</button>
