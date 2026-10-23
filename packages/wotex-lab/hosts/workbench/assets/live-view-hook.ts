type HookLifecycle =
  | "mounted"
  | "beforeUpdate"
  | "updated"
  | "disconnected"
  | "reconnected"
  | "destroyed"

/** LiveView supplies its hook as `this`; application callbacks take that context explicitly. */
export const createLiveViewHook = <Context>(
  callbacks: Partial<Record<HookLifecycle, (context: Context) => unknown>>,
) =>
  Object.fromEntries(
    Object.entries(callbacks).map(([name, callback]) => [
      name,
      new Proxy(callback, { apply: (handler, context) => handler(context) }),
    ]),
  )
