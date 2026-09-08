# Wotex Thread

Consumer-neutral Thread library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

The implemented package provides bounded Operational Dataset TLVs and a real
read-only `ot-daemon` Unix-socket adapter. Dataset inspection redacts key material;
explicit `encode/1` returns the raw bytes. Unknown TLVs are retained, duplicates
are rejected, and known lengths/network-name encoding are validated.
`complete?/2` checks required field presence, not the SDK's full semantic validity.

```elixir
{:ok, session} = Wotex.Thread.connect(
  client: Wotex.Thread.Daemon, socket_path: "/run/openthread-wpan0.sock", timeout: 3000
)
try do
  Wotex.Thread.send(session, %{type: :state})
after
  Wotex.Thread.disconnect(session)
end
```

The caller owns the socket and must use the session from its owning process.
Supported reads are `:state`, `:version`, `:network_name` and `:rloc16`.
Responses are capped at 8192 bytes; remote Error, malformed output, closure and
timeout fail. The package neither starts OpenThread nor changes datasets.
Thread supplies networking, not generic application Property read/write.
Dataset installation, joiner/commissioner workflows, border-router management
and hardware/radio interoperability remain separate graduation gates.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :thread, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; unsupported receive/subscription calls fail
explicitly. Callback names alone do not establish consumer behavioral parity.
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

See [implemented profile](docs/specs/WTH.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Run `mix check` before commits. It includes package compilation outside the
checkout, tests/coverage, static checks, docs and dependency audit.
Optional interoperability suites fail if invoked without their required peer.
No remote repository, published package or publication action is implied.
