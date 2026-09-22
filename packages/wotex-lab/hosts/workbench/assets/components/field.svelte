<script lang="ts">
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
</script>

<div class="wl-control">
  <label for={id}>{label}</label>
  <input
    {id}
    {name}
    {type}
    {value}
    class="wl-field"
    aria-invalid={error ? "true" : undefined}
    aria-describedby={error ? `${id}-error` : undefined}
    {disabled}
    {required}
    oninput={(event) => oninput?.(event.currentTarget.value)}
  />
  {#if error}<p id={`${id}-error`} role="alert">{error}</p>{/if}
</div>
