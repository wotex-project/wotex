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
</script>

<label class="wl-choice" for={id}
  ><input
    {id}
    {name}
    type="checkbox"
    {checked}
    {disabled}
    onchange={(event) => onchange?.(event.currentTarget.checked)}
  /> {label}</label
>
