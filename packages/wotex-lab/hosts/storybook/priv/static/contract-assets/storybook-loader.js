(() => {
  const delegate = Symbol("wotex-lab-storybook-hook")
  const ready = Symbol("wotex-lab-storybook-ready")

  const bridge = {
    async mounted() {
      this[ready] ??= import("/contract-assets/storybook-module.js").then(() => {
        const hook = window.storybook?.Hooks?.WotexLabSvelteIsland
        if (!hook || hook === bridge) throw new Error("Wotex Lab island hook did not load")
        this[delegate] = hook
        return hook
      })

      const hook = await this[ready]
      return hook.mounted?.call(this)
    },
    async updated() {
      const hook = await this[ready]
      return hook.updated?.call(this)
    },
    async disconnected() {
      const hook = await this[ready]
      return hook.disconnected?.call(this)
    },
    async reconnected() {
      const hook = await this[ready]
      return hook.reconnected?.call(this)
    },
    async destroyed() {
      const hook = this[delegate] ?? (await this[ready])
      return hook.destroyed?.call(this)
    },
  }

  const storybook = window.storybook ?? {}
  window.storybook = {
    ...storybook,
    Hooks: {
      ...storybook.Hooks,
      WotexLabSvelteIsland: bridge,
    },
  }
})()
