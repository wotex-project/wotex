const createBridge = () => {
  const delegate = Symbol("wotex-lab-storybook-hook")
  const ready = Symbol("wotex-lab-storybook-ready")
  let bridge

  const mounted = async (context) => {
    context[ready] ??= import("/contract-assets/storybook-module.js").then(() => {
      const hook = window.storybook?.Hooks?.WotexLabSvelteIsland
      if (!hook || hook === bridge) {
        throw new Error("Wotex Lab island hook did not load")
      }
      context[delegate] = hook
      return hook
    })
    const hook = await context[ready]
    return hook.mounted?.call(context)
  }

  const forward = (name) => async (context) => {
    const hook = await context[ready]
    return hook[name]?.call(context)
  }

  const destroyed = async (context) => {
    const hook = context[delegate] ?? (await context[ready])
    return hook.destroyed?.call(context)
  }

  const callbacks = {
    mounted,
    updated: forward("updated"),
    disconnected: forward("disconnected"),
    reconnected: forward("reconnected"),
    destroyed,
  }
  bridge = Object.fromEntries(
    Object.entries(callbacks).map(([name, callback]) => [
      name,
      new Proxy(callback, { apply: (handler, context) => handler(context) }),
    ]),
  )
  return bridge
}

const register = () => {
  const storybook = window.storybook ?? {}
  window.storybook = {
    ...storybook,
    Hooks: {
      ...storybook.Hooks,
      WotexLabSvelteIsland: createBridge(),
    },
  }
}

register()
