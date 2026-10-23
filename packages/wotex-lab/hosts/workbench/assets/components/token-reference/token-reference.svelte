<script lang="ts">
  import { tokenDigest, tokenRoles } from "$lib/design-system/tokens.ts"

  const cssVariable = (name: string) =>
    `--wotex-${name.replaceAll(".", "-").replace(/[A-Z]/g, (character) => `-${character.toLowerCase()}`)}`
</script>

<section class="wl-token-story">
  <h1>Design tokens</h1>
  <p><code>{tokenDigest}</code></p>
  <dl>
    {#each Object.entries(tokenRoles) as [name, role]}
      <div>
        <dt>{name}</dt>
        <dd>
          {#if name.startsWith("semantic.color")}
            <span
              aria-hidden="true"
              style={`display: inline-block; width: 1rem; height: 1rem; background: var(${cssVariable(name)}); border: 1px solid var(--wotex-semantic-color-control-border)`}
            ></span>
          {/if}
          Light: {role.values.light} · Dark: {role.values.dark}
        </dd>
      </div>
    {/each}
  </dl>
</section>
