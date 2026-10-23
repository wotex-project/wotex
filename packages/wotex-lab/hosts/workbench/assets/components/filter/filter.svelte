<script lang="ts">
  import FilterControl from "$lib/components/filter/filter/filter-field.svelte"
  import Button from "$lib/primitives/button/button.svelte"

  export interface FilterField {
    name: string
    label: string
    value?: string
    options?: Array<{
      label: string
      value: string
    }>
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

  const filterId = $props.id()

  const initialValues = () =>
    Object.fromEntries(fields.map((field) => [field.name, field.value ?? ""]))

  let values = $state<Record<string, string>>(initialValues())

  const change = (name: string, value: string) => {
    values = {
      ...values,
      [name]: value,
    }
    onchange?.(values)
  }

  const apply = () => onapply?.(values)
</script>

<fieldset class="wl-panel">
  <legend>{legend}</legend>
  {#each fields as field (field.name)}
    <FilterControl
      id={`${filterId}-${field.name}`}
      {field}
      value={values[field.name]}
      onchange={change}
    />
  {/each}
  <Button unstyled type="button" class="wl-button" onclick={apply}>Apply filters</Button>
</fieldset>
