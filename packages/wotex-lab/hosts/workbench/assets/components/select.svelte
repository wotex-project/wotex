<script lang="ts">
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
</script>

<div class="wl-control">
  <label for={id}>{label}</label>
  <select
    {id}
    {name}
    class="wl-select"
    {value}
    {disabled}
    {required}
    onchange={(event) => onchange?.(event.currentTarget.value)}
  >
    {#each options as option (option.value)}
      <option value={option.value} disabled={option.disabled}>{option.label}</option>
    {/each}
  </select>
</div>
