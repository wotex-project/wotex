<script lang="ts">
export interface FilterField {
  name: string
  label: string
  value?: string
  options?: Array<{ label: string; value: string }>
}

let {
  legend,
  fields,
  onchange,
  onapply,
}: {
  legend: string
  fields: FilterField[]
  onchange?: (values: Record<string, string>) => void
  onapply?: (values: Record<string, string>) => void
} = $props()

const initialValues = () =>
  Object.fromEntries(fields.map((field) => [field.name, field.value ?? ""]))
let values = $state<Record<string, string>>(initialValues())
const change = (name: string, value: string) => {
  values = { ...values, [name]: value }
  onchange?.(values)
}
</script>

<fieldset class="wl-panel">
  <legend>{legend}</legend>
  {#each fields as field (field.name)}
    <label class="wl-control">
      {field.label}
      {#if field.options}
        <select class="wl-select" value={values[field.name]} onchange={(event) => change(field.name, event.currentTarget.value)}>
          {#each field.options as option (option.value)}<option value={option.value}>{option.label}</option>{/each}
        </select>
      {:else}
        <input class="wl-field" value={values[field.name]} oninput={(event) => change(field.name, event.currentTarget.value)} />
      {/if}
    </label>
  {/each}
  <button type="button" class="wl-button" onclick={() => onapply?.(values)}>Apply filters</button>
</fieldset>
