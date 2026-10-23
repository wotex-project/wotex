<script lang="ts">
  import Button from "$lib/primitives/button/button.svelte"

  export interface InspectorField {
    label: string
    value: string
  }

  let {
    title,
    fields,
    open = true,
    onclose,
  }: {
    title: string
    fields: InspectorField[]
    open?: boolean
    onclose?: () => void
  } = $props()
</script>

{#if open}
  <aside class="wl-panel" aria-label={title}>
    <header>
      <h2>{title}</h2>
      {#if onclose}
        <Button
          unstyled
          type="button"
          class="wl-button"
          data-wotex-variant="secondary"
          onclick={onclose}
        >
          Close
        </Button>
      {/if}
    </header>
    <dl>
      {#each fields as field, index (`${field.label}:${index}`)}
        <dt>{field.label}</dt>
        <dd>{field.value}</dd>
      {/each}
    </dl>
  </aside>
{/if}
