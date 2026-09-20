import "@phoenix-assets/svelte/design-system.css"
import { PhoenixAssetsSvelteIsland } from "@phoenix-assets/svelte/islands"

interface PhoenixSocketConstructor {
  new (path: string, options?: Record<string, unknown>): unknown
}

interface LiveSocketInstance {
  connect: () => void
  disconnect: () => void
  isConnected: () => boolean
}

interface LiveSocketConstructor {
  new (
    path: string,
    socket: PhoenixSocketConstructor,
    options: Record<string, unknown>,
  ): LiveSocketInstance
}

declare global {
  interface Window {
    LiveView?: { LiveSocket: LiveSocketConstructor }
    Phoenix?: { Socket: PhoenixSocketConstructor }
    liveSocket?: LiveSocketInstance
  }
}

const csrf = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content

if (window.Phoenix && window.LiveView && csrf) {
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    hooks: { PhoenixAssetsSvelteIsland },
    params: { _csrf_token: csrf },
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
}
