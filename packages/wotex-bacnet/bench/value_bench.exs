Code.require_file("support/values.exs", __DIR__)

alias Wotex.BACnet.Bench.Values
alias Wotex.BACnet.Value

inputs =
  Map.new(Values.cases(), fn {label, type, value, _} ->
    selector = %{"@type" => type}
    encoded = Values.encode!(value, type)
    {label, %{selector: selector, value: value, encoded: encoded}}
  end)

Benchee.run(
  %{
    "encode declared type" => fn %{value: value, selector: selector} ->
      {:ok, _} = Value.encode(value, selector)
    end,
    "validate native write" => fn %{encoded: encoded} -> :ok = Value.validate_write(encoded) end,
    "project result" => fn %{encoded: encoded, value: value} ->
      {^value, %{bacnet_type: _}} = Value.result(encoded)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/value.md",
     title: "# Typed BACnet value conversion",
     description: """
     `Wotex.BACnet.Value` over a `bacv:Real` present-value and `bacv:String`
     values of 64 bytes and 1 KiB. `encode/2` checks the declared scalar type
     and builds the BACstack application-tag encoding; `validate_write/1` is the
     admission every native write passes, which bounds the value structure,
     re-encodes the tag and checks its character set; `result/1` projects the
     value and its BACnet type for a Runtime result. Strings are retained as
     `Wotex.BACnet.CharacterString` values with character set 0 (UTF-8).
     """}
  ]
)
