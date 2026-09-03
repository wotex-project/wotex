# Runtime baseline

Development verification for version 0.1 uses Wotex Runtime commit
`ae21976013e60e542dbe6373c951aa0552100b29` and its released dependency identity
`wotex_runtime ~> 0.1.0`.

The implemented transport boundary is exactly:

```elixir
request(Wotex.Runtime.Request.t(), Wotex.Runtime.ExecutionContext.t(), config)

subscribe(
  Wotex.Runtime.Request.t(),
  pid(),
  Wotex.Runtime.ExecutionContext.t(),
  config
)

unsubscribe(
  handle,
  Wotex.Runtime.Request.t(),
  Wotex.Runtime.ExecutionContext.t(),
  config
)
```

The HTTP profile is created through `Wotex.Runtime.BindingProfile.new/1`.
Runtime request values arrive credential-free; the ephemeral credential exists
only in `ExecutionContext` and is forwarded as a separate immediate client-port
argument. Runtime subscription delivery uses `{:wotex_transport, payload}`.

Executable callback and end-to-end evidence is in
`test/wotex/binding/http/library_contract_test.exs` and
`test/wotex/binding/http/integration_test.exs`.
