import { assertJsonValue, decodedBytes, digestPayload } from "./canonical.js"
import { componentDescriptor } from "./descriptors.js"
import type {
  FullSnapshot,
  IslandEvent,
  JsonValue,
  PatchEnvelope,
  PatchOperation,
} from "./types.js"

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

const exactKeys = (value: object, required: string[], optional: string[] = []) => {
  const admitted = new Set([...required, ...optional])
  const keys = Object.keys(value)
  return required.every((key) => keys.includes(key)) && keys.every((key) => admitted.has(key))
}

const identity = (value: FullSnapshot | PatchEnvelope) => {
  if (
    value.schema !== ISLAND_SCHEMA ||
    !componentDescriptor(value.component) ||
    !boundedIdentifier.test(value.instance_id) ||
    !unsignedDecimal.test(value.generation) ||
    !unsignedDecimal.test(value.revision) ||
    !Array.isArray(value.capabilities) ||
    value.capabilities.length !== new Set(value.capabilities).size ||
    !value.capabilities.every(
      (capability) => typeof capability === "string" && boundedIdentifier.test(capability),
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
  if (!descriptor) throw new Error("unregistered island component")
  assertJsonValue(payload)
  const schemas = descriptor.props as Record<string, Record<string, unknown>>
  for (const key of Object.keys(payload)) {
    const schema = schemas[key]
    if (!schema || !validateProp(schema, payload[key] as JsonValue)) {
      throw new Error(`invalid island field ${key}`)
    }
  }
  for (const [key, schema] of Object.entries(schemas)) {
    if (schema.required === true && !(key in payload)) throw new Error(`missing island field ${key}`)
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
  if (decodedBytes(value) > limits.snapshotBytes) throw new Error("island snapshot exceeds 512 KiB")
  validatePayload(snapshot.component, snapshot.payload)
  if ((await digestPayload(snapshot.payload)) !== snapshot.payload_digest) {
    throw new Error("island payload digest mismatch")
  }
  return snapshot
}

const pointerSegments = (path: string): string[] => {
  if (!path.startsWith("/") || path === "/") throw new Error("invalid island patch path")
  if (/~(?:[^01]|$)/.test(path)) throw new Error("invalid island patch escape")
  const segments = path
    .slice(1)
    .split("/")
    .map((segment) => segment.replaceAll("~1", "/").replaceAll("~0", "~"))
  if (segments.some((segment) => ["__proto__", "prototype", "constructor"].includes(segment))) {
    throw new Error("unsafe island patch path")
  }
  return segments
}

const applyOperation = (payload: Record<string, JsonValue>, operation: PatchOperation) => {
  if (!["add", "remove", "replace"].includes(operation.op))
    throw new Error("unsupported island patch operation")
  if (
    !exactKeys(operation, ["op", "path"], operation.op === "remove" ? [] : ["value"]) ||
    (operation.op !== "remove" && !("value" in operation))
  ) {
    throw new Error("invalid island patch operation fields")
  }
  const segments = pointerSegments(operation.path)
  let parent: JsonValue = payload
  for (const segment of segments.slice(0, -1)) {
    if (Array.isArray(parent)) parent = parent[Number(segment)] as JsonValue
    else if (parent && typeof parent === "object") parent = parent[segment] as JsonValue
    else throw new Error("island patch path does not exist")
  }
  const key = segments.at(-1) as string
  if (Array.isArray(parent)) {
    const index = key === "-" ? parent.length : Number(key)
    if (!Number.isInteger(index) || index < 0 || index > parent.length)
      throw new Error("invalid island array index")
    if (operation.op === "remove") parent.splice(index, 1)
    else if (operation.op === "add") parent.splice(index, 0, operation.value as JsonValue)
    else if (index < parent.length) parent[index] = operation.value as JsonValue
    else throw new Error("island replace path does not exist")
  } else if (parent && typeof parent === "object") {
    if (operation.op !== "add" && !(key in parent))
      throw new Error("island patch path does not exist")
    if (operation.op === "remove") delete parent[key]
    else parent[key] = operation.value as JsonValue
  } else {
    throw new Error("island patch parent does not exist")
  }
}

export type PatchResult = "applied" | "duplicate" | "resync"

export class IslandState {
  #snapshot: FullSnapshot
  #resyncPending = false
  readonly #requestResync: () => void

  constructor(snapshot: FullSnapshot, requestResync: () => void) {
    this.#snapshot = snapshot
    this.#requestResync = requestResync
  }

  get snapshot() {
    return this.#snapshot
  }

  async replace(value: unknown) {
    const snapshot = await validateFullSnapshot(value)
    if (
      snapshot.component !== this.#snapshot.component ||
      snapshot.instance_id !== this.#snapshot.instance_id
    ) {
      throw new Error("island snapshot identity changed")
    }
    this.#snapshot = snapshot
    this.#resyncPending = false
  }

  async patch(value: unknown): Promise<PatchResult> {
    try {
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
        patch.component !== this.#snapshot.component ||
        patch.instance_id !== this.#snapshot.instance_id ||
        patch.generation !== this.#snapshot.generation
      ) {
        throw new Error("island patch identity mismatch")
      }
      if (patch.revision === this.#snapshot.revision) return "duplicate"
      if (
        patch.base_revision !== this.#snapshot.revision ||
        BigInt(patch.revision) !== BigInt(patch.base_revision) + 1n
      ) {
        throw new Error("island patch revision mismatch")
      }
      const payload = structuredClone(this.#snapshot.payload)
      for (const operation of patch.operations) applyOperation(payload, operation)
      validatePayload(patch.component, payload)
      if ((await digestPayload(payload)) !== patch.payload_digest)
        throw new Error("island patch digest mismatch")
      this.#snapshot = { ...patch, payload }
      this.#resyncPending = false
      return "applied"
    } catch {
      if (!this.#resyncPending) {
        this.#resyncPending = true
        this.#requestResync()
      }
      return "resync"
    }
  }
}

export const buildEvent = (
  snapshot: FullSnapshot,
  event: string,
  payload: Record<string, JsonValue>,
  commandId?: string,
): IslandEvent => {
  const descriptor = componentDescriptor(snapshot.component)
  const eventDescriptor = descriptor?.events[event as keyof typeof descriptor.events] as
    | { effectful?: boolean; payload?: string }
    | undefined
  if (!eventDescriptor) throw new Error("unknown island event")
  assertJsonValue(payload)
  const payloadField = eventDescriptor.payload
  if (payloadField === "empty" && Object.keys(payload).length !== 0)
    throw new Error("island event payload must be empty")
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
    ...(commandId ? { command_id: commandId } : {}),
  }
  if (commandId && (!boundedIdentifier.test(commandId) || commandId.length > 512)) {
    throw new Error("invalid island command id")
  }
  if (eventDescriptor.effectful && !commandId)
    throw new Error("effectful island event requires a command id")
  if (decodedBytes(envelope as unknown as JsonValue) > limits.eventBytes)
    throw new Error("island event exceeds 32 KiB")
  return envelope
}
