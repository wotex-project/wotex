<script lang="ts">
  let {
    id,
    name,
    label,
    checked = false,
    disabled = false,
    onchange,
  }: {
    id: string
    name: string
    label: string
    checked?: boolean
    disabled?: boolean
    onchange?: (checked: boolean) => void
  } = $props()

  const handleChange = (event: Event & { currentTarget: HTMLInputElement }) =>
    onchange?.(event.currentTarget.checked)
</script>

<label class="wl-choice" for={id}
  ><input {id} {name} type="checkbox" {checked} {disabled} onchange={handleChange}> {label}</label
>
