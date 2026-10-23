<script lang="ts">
  import Input from "$lib/primitives/input/input.svelte"

  let {
    id,
    name,
    label,
    value = "",
    type = "text",
    error,
    disabled = false,
    required = false,
    oninput,
  }: {
    id: string
    name: string
    label: string
    value?: string
    type?: "text" | "search" | "email" | "password" | "url" | "number"
    error?: string
    disabled?: boolean
    required?: boolean
    oninput?: (value: string) => void
  } = $props()

  const handleChange = (event: Event & { currentTarget: HTMLInputElement }) =>
    oninput?.(event.currentTarget.value)
</script>

<div class="wl-control">
  <label for={id}>{label}</label>
  <Input
    {id}
    {name}
    {type}
    {value}
    class="wl-field"
    aria-invalid={error ? "true" : undefined}
    aria-describedby={error ? `${id}-error` : undefined}
    {disabled}
    {required}
    oninput={handleChange}
  />
  {#if error}
    <p id={`${id}-error`} role="alert">{error}</p>
  {/if}
</div>
