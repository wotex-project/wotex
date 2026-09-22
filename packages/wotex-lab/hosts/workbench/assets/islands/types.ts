import type { Component } from "svelte"

export type JsonScalar = null | boolean | number | string
export type JsonValue = JsonScalar | JsonValue[] | { [key: string]: JsonValue }

export interface IslandIdentity {
  schema: "wotex-lab-island/v1"
  component: string
  instance_id: string
  generation: string
  revision: string
  capabilities: string[]
}

export interface FullSnapshot extends IslandIdentity {
  payload_digest: string
  payload: Record<string, JsonValue>
}

export interface PatchEnvelope extends IslandIdentity {
  base_revision: string
  payload_digest: string
  operations: PatchOperation[]
}

export interface PatchOperation {
  op: "add" | "remove" | "replace"
  path: string
  value?: JsonValue
}

export interface IslandEvent {
  schema: "wotex-lab-island-event/v1"
  component: string
  instance_id: string
  client_revision: string
  event: string
  command_id?: string
  payload: Record<string, JsonValue>
}

export interface IslandTransport {
  connected: () => boolean
  navigate: (kind: "navigate" | "patch", href: string) => void
  push: (
    event: string,
    payload: Record<string, JsonValue>,
    commandId?: string,
  ) => Promise<JsonValue>
}

export interface IslandInstance {
  update?: (payload: Record<string, JsonValue>) => void
  setConnected?: (connected: boolean) => void
}

export type IslandComponent = Component<
  { payload: Record<string, JsonValue>; transport: IslandTransport },
  IslandInstance
>

export interface IslandModule {
  default: IslandComponent
}

export type IslandLoader = () => Promise<IslandModule>
