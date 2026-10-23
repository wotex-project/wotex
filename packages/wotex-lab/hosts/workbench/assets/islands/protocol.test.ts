import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { after, test } from "node:test"
import { createServer } from "vite"
import type { FullSnapshot, JsonValue, PatchEnvelope } from "./types.js"

interface Fixture {
  canonical: {
    id: string
    value: JsonValue
    canonical: string
    digest: string
  }[]
  transition: {
    next_payload: Record<string, JsonValue>
    snapshot: FullSnapshot
    patch: PatchEnvelope
  }
}

const fixture = JSON.parse(
  await readFile(new URL("../../test/support/island_protocol.json", import.meta.url), "utf8"),
) as Fixture
const server = await createServer({
  configFile: false,
  server: { middlewareMode: true, watch: null, ws: false },
})
after(() => server.close())
const canonical: typeof import("./canonical.js") = (await server.ssrLoadModule(
  new URL("./canonical.ts", import.meta.url).pathname,
)) as typeof import("./canonical.js")
const protocol: typeof import("./protocol.js") = (await server.ssrLoadModule(
  new URL("./protocol.ts", import.meta.url).pathname,
)) as typeof import("./protocol.js")

test("canonical bytes and SHA-256 digests agree with the Elixir vectors", async () => {
  for (const vector of fixture.canonical) {
    canonical.assertJsonValue(vector.value)
    assert.equal(canonical.canonicalize(vector.value), vector.canonical, vector.id)
    const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(vector.canonical))
    assert.equal(Buffer.from(bytes).toString("hex"), vector.digest)
  }
  for (const value of ["\ud800", "prefix\udbff", "\udc00", "\ud800x", "\ud800\ud800"]) {
    assert.throws(() => canonical.assertJsonValue(value), /unpaired surrogate/)
    assert.throws(() => canonical.assertJsonValue({ [value]: "key" }), /unpaired surrogate/)
  }
  assert.doesNotThrow(() => canonical.assertJsonValue("\ud83d\ude00"))
})

test("the browser applies the exact server snapshot and patch without losing Unicode or escaped keys", async () => {
  const { snapshot, patch, next_payload: expected } = fixture.transition
  const original = structuredClone(snapshot)
  const accepted = await protocol.validateFullSnapshot(snapshot)
  let resyncs = 0
  const state = new protocol.IslandState(accepted, () => resyncs++)
  assert.equal(await state.patch(patch), "applied")
  assert.deepEqual(state.snapshot.payload, expected)
  assert.equal(await state.patch(patch), "duplicate")
  assert.equal(resyncs, 0)
  assert.equal("operations" in state.snapshot, false)
  assert.equal("base_revision" in state.snapshot, false)
  assert.deepEqual(snapshot, original)
})

test("invalid array paths retain the base and request one full snapshot", async () => {
  const { snapshot, patch } = fixture.transition
  const paths = [
    "/rows/01",
    "/rows/1e0",
    "/rows/+0",
    "/rows/-1",
    "/rows/0.0",
    "/rows/0x0",
    "/rows/1",
    "/rows/-",
    "/rows/99/values",
    "/rows/01/values",
    "/rows/0\n",
  ]
  for (const path of paths) {
    let resyncs = 0
    const state = new protocol.IslandState(snapshot, () => resyncs++)
    // An unchanged digest must not turn an invalid no-op remove into an accepted patch.
    const invalid = {
      ...patch,
      payload_digest: snapshot.payload_digest,
      operations: [{ op: "remove", path }],
    }
    assert.equal(await state.patch(invalid), "resync", path)
    assert.equal(await state.patch(invalid), "resync", path)
    assert.equal(resyncs, 1, path)
    assert.equal(state.snapshot, snapshot)
    await state.replace(snapshot)
    assert.equal(await state.patch(patch), "applied")
  }
})

test("snapshot identities are strings with no trailing line terminators", async () => {
  const { snapshot } = fixture.transition
  for (const field of ["generation", "revision", "instance_id"] as const) {
    for (const value of [
      0,
      `${snapshot[field]}\n`,
      `${snapshot[field]}\r`,
      `${snapshot[field]}\u2028`,
    ]) {
      await assert.rejects(protocol.validateFullSnapshot({ ...snapshot, [field]: value }))
    }
  }
  await assert.rejects(protocol.validateFullSnapshot({ ...snapshot, capabilities: ["read\n"] }))
  await assert.rejects(protocol.validateFullSnapshot({ ...snapshot, payload: [] }))
})

test("a stale full snapshot cannot rewind a validated patch or reset its generation", async () => {
  const { snapshot, patch } = fixture.transition
  const state = new protocol.IslandState(snapshot, () => {})
  assert.equal(await state.patch(patch), "applied")
  await assert.rejects(state.replace(snapshot), /stale or contradictory/)
  assert.equal(state.snapshot.revision, "1")
  const nextGeneration = { ...snapshot, generation: "1" }
  await state.replace(nextGeneration)
  await assert.rejects(state.replace(snapshot), /stale or contradictory/)
  assert.equal(state.snapshot, nextGeneration)
})

test("concurrent patch validation cannot overwrite a newer accepted snapshot", async () => {
  const { snapshot, patch } = fixture.transition
  let resyncs = 0
  const state = new protocol.IslandState(snapshot, () => resyncs++)
  const results = await Promise.all([state.patch(patch), state.patch(patch)])
  assert.deepEqual(results.sort(), ["applied", "resync"])
  assert.equal(state.snapshot.revision, "1")
  assert.equal(resyncs, 1)
})
