<script lang="ts">
export interface NavigationItem {
  id: string
  title: string
  path: string
  children?: NavigationItem[]
}

let { label, items, current }: { label: string; items: NavigationItem[]; current?: string } =
  $props()
</script>

<nav aria-label={label}>
  <ul>
    {#each items as item (item.id)}
      <li>
        <a href={item.path} aria-current={item.path === current ? "page" : undefined}>{item.title}</a>
        {#if item.children?.length}
          <ul>
            {#each item.children as child (child.id)}
              <li><a href={child.path} aria-current={child.path === current ? "page" : undefined}>{child.title}</a></li>
            {/each}
          </ul>
        {/if}
      </li>
    {/each}
  </ul>
</nav>
