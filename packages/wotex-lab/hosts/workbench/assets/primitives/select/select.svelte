<script lang="ts">
  import SelectControl from "$lib/primitives/select/select-control.svelte"

  export interface SelectOption {
    label: string
    value: string
    disabled?: boolean
  }

  let {
    id,
    name,
    label,
    value = "",
    options,
    disabled = false,
    required = false,
    onchange,
  }: {
    id: string
    name: string
    label: string
    value?: string
    options: SelectOption[]
    disabled?: boolean
    required?: boolean
    onchange?: (value: string) => void
  } = $props()

  const handleChange = (event: Event & { currentTarget: HTMLSelectElement }) =>
    onchange?.(event.currentTarget.value)
</script>

<div class="wl-control">
  <label for={id}>{label}</label>
  <SelectControl
    {id}
    {name}
    class="wl-select"
    {value}
    {disabled}
    {required}
    onchange={handleChange}
  >
    {#each options as option (option.value)}
      <option value={option.value} disabled={option.disabled}>{option.label}</option>
    {/each}
  </SelectControl>
</div>
