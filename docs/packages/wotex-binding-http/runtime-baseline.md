# Runtime baseline

Development verification for version 0.1 uses Wotex Runtime commit
`70f9511b8b691665b0c87d84f743891c70c93b9e` and its released dependency identity
`wotex_runtime ~> 0.1.0`. Bounded JSON admission comes from Wotex core commit
`58409779ae9515df2bf120a5f13813cffcb1c59c` and `wotex ~> 0.1.0`. Both commits
belong to the former per-package repositories and predate the move into this
repository; the package gate now builds against the `wotex` and
`wotex-runtime` packages of the same commit.

The implemented transport boundary is exactly:

```elixir
request(Wotex.Runtime.Request.t(), Wotex.Runtime.ExecutionContext.t(), config)

subscribe(
  Wotex.Runtime.Request.t(),
  owner :: pid(),
  Wotex.Runtime.ExecutionContext.t(),
  config
)

unsubscribe(
  handle,
  Wotex.Runtime.Request.t(),
  Wotex.Runtime.ExecutionContext.t(),
  config
)

decode_frame(frame, Wotex.Runtime.Request.t(), config)
```

The HTTP profile is created through `Wotex.Runtime.BindingProfile.new/1`.
Runtime request values arrive credential-free; the ephemeral credential exists
only in `ExecutionContext` and is forwarded as a separate immediate client-port
argument.

Subscription messages are exactly:

| Direction | Message |
| --- | --- |
| client to owner | `{:wotex_transport_frame, %Wotex.Binding.HTTP.SSE.Event{}}` |
| client to owner | `{:wotex_transport_status, :reconnected \| :session_lost \| :transport_down}` |
| Runtime to receiver | `{:wotex_runtime, subscription_id, {:ok, data, meta}}` |
| Runtime to receiver | `{:wotex_runtime, subscription_id, {:error, %Wotex.Runtime.Error{}}}` |
| Runtime to receiver | `{:wotex_runtime, subscription_id, {:status, status}}` |

`decode_frame/3` runs in the owner process and returns `{:ok, data, meta}`,
`:ignore`, or a classified `Wotex.Binding.HTTP.Error`. Runtime result status is
`:ok` or `:accepted`; the HTTP status code is `metadata.http.status`. Runtime
copies a binding error's `code`, `phase`, and `class` into `details.cause`.

Executable callback and end-to-end evidence is in
`test/wotex/binding/http/library_contract_test.exs` and
`test/wotex/binding/http/integration_test.exs`.
