<script lang="ts">
export interface RadioOption {
  label: string
  value: string
  disabled?: boolean
}

let {
  name,
  legend,
  value = "",
  options,
  disabled = false,
  onchange,
}: {
  name: string
  legend: string
  value?: string
  options: RadioOption[]
  disabled?: boolean
  onchange?: (value: string) => void
} = $props()
</script>

<fieldset disabled={disabled}>
  <legend>{legend}</legend>
  {#each options as option (option.value)}
    <label class="wl-choice"
      ><input
        type="radio"
        {name}
        value={option.value}
        checked={option.value === value}
        disabled={option.disabled}
        onchange={() => onchange?.(option.value)}
      /> {option.label}</label
    >
  {/each}
</fieldset>
