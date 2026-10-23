import componentSeeds from "../../priv/seeds/components.json"
import seedData from "../../priv/seeds/islands.json"
import { componentDescriptors, componentDigest } from "../components/descriptors.js"
import type { IslandTransport, JsonValue } from "../islands/types.js"

export const islandStory = (component: keyof typeof seedData, state = "connected") => {
  const states: Record<string, Record<string, JsonValue>> = seedData[component]
  const payload = states[state]
  if (!payload) {
    throw new Error(`unknown island story: ${component}/${state}`)
  }
  return structuredClone(payload)
}

export const componentStory = <
  Component extends keyof typeof componentSeeds,
  State extends keyof (typeof componentSeeds)[Component] & string,
>(
  component: Component,
  state: State,
) => {
  const args = componentSeeds[component][state]
  if (!args) {
    throw new Error(`unknown component story: ${component}/${state}`)
  }
  return structuredClone(args)
}

export interface RecordedStoryEvent {
  event: string
  payload: Record<string, JsonValue>
  commandId?: string
}

export interface StoryTransport extends IslandTransport {
  events: RecordedStoryEvent[]
  disconnect: () => void
  reconnect: () => void
  failNext: (message: string) => void
}

export const createStoryTransport = (replies: Record<string, JsonValue> = {}): StoryTransport => {
  let connected = true
  let failure: string | undefined
  const events: RecordedStoryEvent[] = []

  return {
    events,
    connected: () => connected,
    disconnect: () => {
      connected = false
    },
    reconnect: () => {
      connected = true
    },
    failNext: (message) => {
      failure = message
    },
    navigate: (_, href) => {
      if (!href.startsWith("/")) {
        throw new Error("story navigation must stay on the current origin")
      }
    },
    push: async (event, payload, commandId) => {
      events.push({
        event,
        payload,
        ...(commandId
          ? {
              commandId,
            }
          : {}),
      })
      if (!connected) {
        throw new Error("story transport is disconnected")
      }
      if (failure) {
        const message = failure
        failure = undefined
        throw new Error(message)
      }
      return replies[event] ?? null
    },
  }
}

export const storyFixtures = componentDescriptors.map((descriptor) => ({
  schema: "wotex-lab-story/v1" as const,
  id: descriptor.story_id,
  component: descriptor.id,
  descriptor_digest: componentDigest,
  states: descriptor.states,
  fallback: descriptor.fallback,
}))

export const storyFixture = (component: string) => {
  const fixture = storyFixtures.find((candidate) => candidate.component === component)
  if (!fixture) {
    throw new Error(`unknown Storybook fixture: ${component}`)
  }
  return fixture
}
