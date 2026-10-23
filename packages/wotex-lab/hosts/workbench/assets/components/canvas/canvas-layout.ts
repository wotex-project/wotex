import type { Node } from "@xyflow/svelte"
import type { CanvasPin } from "$lib/islands/canvas-model.ts"

export const pinGeometry = (pin: CanvasPin, previous: Node | undefined, restore: boolean) => ({
  position: restore ? { x: pin.x, y: pin.y } : (previous?.position ?? { x: pin.x, y: pin.y }),
  width: restore ? pin.width : (previous?.width ?? pin.width),
  height: restore ? pin.height : (previous?.height ?? pin.height),
})
