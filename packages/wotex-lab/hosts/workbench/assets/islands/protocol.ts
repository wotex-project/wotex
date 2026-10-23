import { assertJsonValue, decodedBytes, digestPayload } from "$lib/islands/canonical.ts"
import { validateCanvas } from "$lib/islands/canvas-model.ts"
import { componentDescriptor } from "$lib/islands/descriptors.ts"
import type {
  FullSnapshot,
  IslandEvent,
  JsonValue,
  PatchEnvelope,
  PatchOperation,
} from "$lib/islands/types.ts"

export const ISLAND_SCHEMA = "wotex-lab-island/v1" as const
export const ISLAND_EVENT_SCHEMA = "wotex-lab-island-event/v1" as const
export const limits = {
  inlineSnapshotBytes: 32 * 1024,
  snapshotBytes: 512 * 1024,
  patchBytes: 128 * 1024,
  patchOperations: 256,
  eventBytes: 32 * 1024,
} as const

const unsignedDecimal = /^(?:0|[1-9][0-9]*)$/
const boundedIdentifier = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/

const exactMatch = (pattern: RegExp, value: string) => pattern.exec(value)?.[0] === value

const exactKeys = (value: object, required: string[], optional: string[] = []) => {
  const admitted = new Set([...required, ...optional])
  const keys = Object.keys(value)
  return required.every((key) => keys.includes(key)) && keys.every((key) => admitted.has(key))
}

const identity = (value: FullSnapshot | PatchEnvelope) => {
  if (
    value.schema !== ISLAND_SCHEMA ||
    typeof value.component !== "string" ||
    !componentDescriptor(value.component) ||
    typeof value.instance_id !== "string" ||
    !exactMatch(boundedIdentifier, value.instance_id) ||
    typeof value.generation !== "string" ||
    !exactMatch(unsignedDecimal, value.generation) ||
    typeof value.revision !== "string" ||
    !exactMatch(unsignedDecimal, value.revision) ||
    !Array.isArray(value.capabilities) ||
    value.capabilities.length !== new Set(value.capabilities).size ||
    !value.capabilities.every(
      (capability) => typeof capability === "string" && exactMatch(boundedIdentifier, capability),
    )
  ) {
    throw new Error("invalid island identity")
  }
}

const validateProp = (schema: Record<string, unknown>, value: JsonValue) => {
  switch (schema.type) {
    case "string":
      return (
        typeof value === "string" &&
        new TextEncoder().encode(value).byteLength <= Number(schema.max_bytes ?? 8192)
      )
    case "item_list":
      return Array.isArray(value) && value.length <= Number(schema.max_items ?? 2000)
    default:
      return false
  }
}

export const validatePayload = (component: string, payload: Record<string, JsonValue>) => {
  const descriptor = componentDescriptor(component)
  if (!descriptor) {
    throw new Error("unregistered island component")
  }
  assertJsonValue(payload)
  if (!payload || Array.isArray(payload) || typeof payload !== "object") {
    throw new Error("island payload must be an object")
  }
  const schemas = descriptor.props as Record<string, Record<string, unknown>>
  for (const key of Object.keys(payload)) {
    const schema = schemas[key]
    if (!schema || !validateProp(schema, payload[key] as JsonValue)) {
      throw new Error(`invalid island field ${key}`)
    }
  }
  for (const [key, schema] of Object.entries(schemas)) {
    if (schema.required === true && !(key in payload)) {
      throw new Error(`missing island field ${key}`)
    }
  }
  if (component === "canvas") {
    validateCanvas(payload)
  }
}

export const validateFullSnapshot = async (value: unknown): Promise<FullSnapshot> => {
  assertJsonValue(value)
  if (!value || Array.isArray(value) || typeof value !== "object" || !("payload" in value)) {
    throw new Error("invalid island snapshot")
  }
  const snapshot = value as unknown as FullSnapshot
  if (
    !exactKeys(snapshot, [
      "schema",
      "component",
      "instance_id",
      "generation",
      "revision",
      "payload_digest",
      "payload",
      "capabilities",
    ])
  ) {
    throw new Error("invalid island snapshot fields")
  }

  identity(snapshot)
  if (decodedBytes(value) > limits.snapshotBytes) {
    throw new Error("island snapshot exceeds 512 KiB")
  }

  validatePayload(snapshot.component, snapshot.payload)
  if ((await digestPayload(snapshot.payload)) !== snapshot.payload_digest) {
    throw new Error("island payload digest mismatch")
  }

  return snapshot
}

const pointerSegments = (path: string): string[] => {
  if (!path.startsWith("/") || path === "/") {
    throw new Error("invalid island patch path")
  }

  if (/~(?:[^01]|$)/.test(path)) {
    throw new Error("invalid island patch escape")
  }

  const segments = path
    .slice(1)
    .split("/")
    .map((segment) => segment.replaceAll("~1", "/").replaceAll("~0", "~"))
  if (segments.some((segment) => ["__proto__", "prototype", "constructor"].includes(segment))) {
    throw new Error("unsafe island patch path")
  }

  return segments
}

const validateOperation = (operation: PatchOperation) => {
  if (!["add", "remove", "replace"].includes(operation.op)) {
    throw new Error("unsupported island patch operation")
  }

  if (
    !exactKeys(operation, ["op", "path"], operation.op === "remove" ? [] : ["value"]) ||
    (operation.op !== "remove" && !("value" in operation))
  ) {
    throw new Error("invalid island patch operation fields")
  }
}

const patchParent = (payload: Record<string, JsonValue>, segments: string[]) => {
  let parent: JsonValue = payload

  for (const segment of segments.slice(0, -1)) {
    if (Array.isArray(parent)) {
      parent = parent[arrayIndex(segment, parent.length, false)] as JsonValue
    } else if (parent && typeof parent === "object" && Object.hasOwn(parent, segment)) {
      parent = parent[segment] as JsonValue
    } else {
      throw new Error("island patch path does not exist")
    }
  }

  return parent
}

const arrayIndex = (key: string, length: number, append: boolean): number => {
  if (append && key === "-") {
    return length
  }
  const index = Number(key)
  if (
    !exactMatch(unsignedDecimal, key) ||
    !Number.isSafeInteger(index) ||
    index >= length + (append ? 1 : 0)
  ) {
    throw new Error("invalid island array index")
  }
  return index
}

const applyArrayOperation = (parent: JsonValue[], key: string, operation: PatchOperation) => {
  const index = arrayIndex(key, parent.length, operation.op === "add")
  if (operation.op === "remove") {
    parent.splice(index, 1)
  } else if (operation.op === "add") {
    parent.splice(index, 0, operation.value as JsonValue)
  } else if (index < parent.length) {
    parent[index] = operation.value as JsonValue
  } else {
    throw new Error("island replace path does not exist")
  }
}

const applyObjectOperation = (
  parent: Record<string, JsonValue>,
  key: string,
  operation: PatchOperation,
) => {
  if (operation.op !== "add" && !Object.hasOwn(parent, key)) {
    throw new Error("island patch path does not exist")
  }
  if (operation.op === "remove") {
    delete parent[key]
  } else {
    parent[key] = operation.value as JsonValue
  }
}

const applyOperation = (payload: Record<string, JsonValue>, operation: PatchOperation) => {
  validateOperation(operation)
  const segments = pointerSegments(operation.path)
  const parent = patchParent(payload, segments)
  const key = segments.at(-1) as string
  if (Array.isArray(parent)) {
    applyArrayOperation(parent, key, operation)
  } else if (parent && typeof parent === "object") {
    applyObjectOperation(parent, key, operation)
  } else {
    throw new Error("island patch parent does not exist")
  }
}

export type PatchResult = "applied" | "duplicate" | "resync"

const validatePatchEnvelope = (value: unknown, snapshot: FullSnapshot): PatchEnvelope => {
  assertJsonValue(value)
  const patch = value as unknown as PatchEnvelope
  identity(patch)
  if (
    !exactKeys(patch, [
      "schema",
      "component",
      "instance_id",
      "generation",
      "revision",
      "base_revision",
      "payload_digest",
      "operations",
      "capabilities",
    ])
  ) {
    throw new Error("invalid island patch fields")
  }
  if (
    decodedBytes(value) > limits.patchBytes ||
    !Array.isArray(patch.operations) ||
    patch.operations.length > limits.patchOperations
  ) {
    throw new Error("island patch exceeds its limit")
  }
  if (
    patch.component !== snapshot.component ||
    patch.instance_id !== snapshot.instance_id ||
    patch.generation !== snapshot.generation
  ) {
    throw new Error("island patch identity mismatch")
  }

  return patch
}

export const createIslandState = (snapshot: FullSnapshot, requestResync: () => void) => {
  let current = snapshot
  let resyncPending = false

  const replace = async (value: unknown) => {
    const snapshot = await validateFullSnapshot(value)
    if (snapshot.component !== current.component || snapshot.instance_id !== current.instance_id) {
      throw new Error("island snapshot identity changed")
    }
    const generation = BigInt(snapshot.generation)
    const currentGeneration = BigInt(current.generation)
    if (
      generation < currentGeneration ||
      (generation === currentGeneration &&
        (BigInt(snapshot.revision) < BigInt(current.revision) ||
          (snapshot.revision === current.revision &&
            snapshot.payload_digest !== current.payload_digest)))
    ) {
      throw new Error("island snapshot is stale or contradictory")
    }
    current = snapshot
    resyncPending = false
  }

  const patch = async (value: unknown): Promise<PatchResult> => {
    try {
      const patch = validatePatchEnvelope(value, current)
      if (patch.revision === current.revision) {
        return "duplicate"
      }
      if (
        patch.base_revision !== current.revision ||
        BigInt(patch.revision) !== BigInt(patch.base_revision) + 1n
      ) {
        throw new Error("island patch revision mismatch")
      }
      const base = current
      const payload = structuredClone(base.payload)
      for (const operation of patch.operations) {
        applyOperation(payload, operation)
      }
      validatePayload(patch.component, payload)
      if ((await digestPayload(payload)) !== patch.payload_digest) {
        throw new Error("island patch digest mismatch")
      }
      if (current !== base) {
        throw new Error("island patch base changed during validation")
      }
      current = {
        schema: patch.schema,
        component: patch.component,
        instance_id: patch.instance_id,
        generation: patch.generation,
        revision: patch.revision,
        payload_digest: patch.payload_digest,
        capabilities: patch.capabilities,
        payload,
      }
      resyncPending = false
      return "applied"
    } catch {
      if (!resyncPending) {
        resyncPending = true
        requestResync()
      }
      return "resync"
    }
  }

  return { snapshot: () => current, replace, patch }
}

export const buildEvent = (
  snapshot: FullSnapshot,
  event: string,
  payload: Record<string, JsonValue>,
  commandId?: string,
): IslandEvent => {
  const descriptor = componentDescriptor(snapshot.component)
  const eventDescriptor = descriptor?.events[event as keyof typeof descriptor.events] as
    | {
        effectful?: boolean
        payload?: string
      }
    | undefined
  if (!eventDescriptor) {
    throw new Error("unknown island event")
  }
  assertJsonValue(payload)
  const payloadField = eventDescriptor.payload
  if (payloadField === "empty" && Object.keys(payload).length !== 0) {
    throw new Error("island event payload must be empty")
  }
  if (payloadField && payloadField !== "empty" && !exactKeys(payload, [payloadField])) {
    throw new Error(`island event payload requires ${payloadField}`)
  }
  const envelope: IslandEvent = {
    schema: ISLAND_EVENT_SCHEMA,
    component: snapshot.component,
    instance_id: snapshot.instance_id,
    client_revision: snapshot.revision,
    event,
    payload,
    ...(commandId
      ? {
          command_id: commandId,
        }
      : {}),
  }
  if (commandId && (!exactMatch(boundedIdentifier, commandId) || commandId.length > 512)) {
    throw new Error("invalid island command id")
  }
  if (eventDescriptor.effectful && !commandId) {
    throw new Error("effectful island event requires a command id")
  }
  if (decodedBytes(envelope as unknown as JsonValue) > limits.eventBytes) {
    throw new Error("island event exceeds 32 KiB")
  }
  return envelope
}
