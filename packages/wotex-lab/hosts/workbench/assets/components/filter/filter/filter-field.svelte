<script lang="ts">
  import type { FilterField } from "$lib/components/filter/filter.svelte"
  import Input from "$lib/primitives/input/input.svelte"
  import SelectControl from "$lib/primitives/select/select-control.svelte"

  let {
    id,
    field,
    value,
    onchange,
  }: {
    id: string
    field: FilterField
    value: string | undefined
    onchange: (name: string, value: string) => void
  } = $props()

  const change = (event: Event & { currentTarget: HTMLInputElement | HTMLSelectElement }) =>
    onchange(field.name, event.currentTarget.value)
</script>

<label class="wl-control" for={id}>
  {field.label}
  {#if field.options}
    <SelectControl {id} class="wl-select" {value} onchange={change}>
      {#each field.options as option (option.value)}
        <option value={option.value}>{option.label}</option>
      {/each}
    </SelectControl>
  {:else}
    <Input {id} class="wl-field" {value} oninput={change} />
  {/if}
</label>
