# Wotex UDP package guidance

This package owns generic bounded datagram transport under WUD.01. It does not
interpret payloads or define a Web of Things binding. The root `AGENTS.md`
also applies.

- Keep sockets in an explicitly started, consumer-owned process. Construction
  is inert; `open/1` is explicit, and the consumer closes or supervises the
  owner.
- Require concrete local and remote addresses. Broadcast and multicast are
  explicitly admitted; never infer policy from an application environment.
- Preserve finite datagram, kernel receive-buffer, batch and deadline bounds.
- Keep errors typed and payload-free. No implicit retry, listener, callback,
  protocol parser, or OTP Application callback.
- Run `mix pkg wotex-udp test`, then `mix check.fast --package wotex-udp`.

Specification: `docs/packages/wotex-udp/specs/WUD.01-datagram-transport.md`.
