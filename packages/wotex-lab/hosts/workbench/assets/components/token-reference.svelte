<script lang="ts">
import { tokenDigest, tokenRoles } from "./tokens.js"

const cssVariable = (name: string) =>
  `--wotex-${name.replaceAll(".", "-").replace(/[A-Z]/g, (character) => `-${character.toLowerCase()}`)}`
</script>

<section data-wotex-design-system class="wl-token-story">
  <h1>Design tokens</h1>
  <p><code>{tokenDigest}</code></p>
  <dl>
    {#each Object.entries(tokenRoles) as [name, role]}
      <div>
        <dt>{name}</dt>
        <dd style:color={name.startsWith("semantic.color") ? `var(${cssVariable(name)})` : undefined}>
          {role.values.light}
        </dd>
      </div>
    {/each}
  </dl>
</section>
