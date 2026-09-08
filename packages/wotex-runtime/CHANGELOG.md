# Changelog

## 0.1.0

- Stop on malformed or ambiguous retry options and unknown operations; require
  positive attempt counts and explicit boolean idempotence without raising.

- Remove the stale `EEF-CVE-2026-32686` Hex advisory suppression now that the
  registry audit reports no matching advisory. Exact Decimal 3.1.1 lock,
  loaded-version and default-parser regression checks remain active.

- Open subscriptions in a continuation, monitor the receiver, stop on linked
  transport exit or `session_lost`/`transport_down` status, always attempt
  unsubscribe at close, and add an opt-in receiver mailbox bound.
- Deliver `{:wotex_runtime, id, {:ok, value, meta} | {:error, error} |
  {:status, status}}` and decode raw frames through `Transport.decode_frame/3`.
- Retain a port error's `code`/`phase`/`class` as `details.cause`, add `class`
  to `Wotex.Runtime.Error`, and let `Retry.decision/3` take an error.
- Isolate raised or exited port callbacks as `port_exception` and emit
  `[:wotex, :runtime, ...]` telemetry for requests, ports and subscriptions.
- Restrict `Result.status` to `:ok | :accepted`; define deadline clocks and
  `Context.remaining_ms/2`; default subscription restart to `:transient`.
- Apply TD 1.1 default Form operations during selection.
- Add caller-owned ConsumedThing and ExposedThing interaction mechanics.
- Add deterministic Form and binding-profile selection.
- Add explicit credential and transport behaviours.
- Add caller-supervised Property observations and Event subscriptions.
