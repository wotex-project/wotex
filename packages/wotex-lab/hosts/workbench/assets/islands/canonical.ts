import type { JsonValue } from "./types.js"

const encoder = new TextEncoder()
const forbiddenKeys =
  /(?:^|_)(?:authorization|cookie|credential|password|secret|socket|token)(?:_|$)/i

const assertString = (value: string) => {
  if (encoder.encode(value).byteLength > 8192) throw new Error("island string exceeds 8192 bytes")
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index)
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1)
      if (next < 0xdc00 || next > 0xdfff)
        throw new Error("island string contains an unpaired surrogate")
      index++
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw new Error("island string contains an unpaired surrogate")
    }
  }
}

export const assertJsonValue: (value: unknown, depth?: number) => asserts value is JsonValue = (
  value,
  depth = 0,
) => {
  if (depth > 16) throw new Error("island value exceeds 16 levels")
  if (value === null || typeof value === "boolean") return
  if (typeof value === "string") {
    assertString(value)
    return
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || (Number.isInteger(value) && !Number.isSafeInteger(value))) {
      throw new Error("island number is outside the I-JSON domain")
    }
    return
  }
  if (Array.isArray(value)) {
    for (const item of value) assertJsonValue(item, depth + 1)
    return
  }
  if (typeof value !== "object") throw new Error("island value is not JSON")
  const prototype = Object.getPrototypeOf(value)
  if (prototype !== Object.prototype && prototype !== null)
    throw new Error("island object is not plain")
  for (const [key, item] of Object.entries(value)) {
    assertString(key)
    if (forbiddenKeys.test(key)) throw new Error("island object contains a secret-bearing field")
    assertJsonValue(item, depth + 1)
  }
}

export const canonicalize = (value: JsonValue): string => {
  if (value === null || typeof value !== "object") return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalize(value[key] as JsonValue)}`)
    .join(",")}}`
}

export const digestPayload = async (payload: Record<string, JsonValue>): Promise<string> => {
  assertJsonValue(payload)
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(canonicalize(payload)))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")
}

export const decodedBytes = (value: JsonValue): number =>
  encoder.encode(canonicalize(value)).byteLength

export const decodeBase64Url = (encoded: string): unknown => {
  const padded = encoded
    .replaceAll("-", "+")
    .replaceAll("_", "/")
    .padEnd(Math.ceil(encoded.length / 4) * 4, "=")
  const bytes = Uint8Array.from(atob(padded), (character) => character.charCodeAt(0))
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))
}
