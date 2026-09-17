defmodule Wotex.OPCUA.StandaloneContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.{Address, Binary, Error}

  @external_resource Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @corpus File.read!(@external_resource)
  @digest Base.encode16(:crypto.hash(:sha256, @corpus), case: :lower)
  @cases Map.fetch!(Jason.decode!(@corpus), "cases")
  @operations %{
    "Binary.decode_node_id/1" => :decode_node_id,
    "Binary.decode_expanded_node_id/1" => :decode_expanded_node_id,
    "Binary.decode_reference_description/1" => :decode_reference_description,
    "Binary.decode_variant/1" => :decode_variant,
    "Binary.decode_data_value/1" => :decode_data_value
  }

  for fixture <- @cases,
      Map.has_key?(@operations, fixture["operation"]) do
    @tag corpus_sha256: @digest
    @tag requirement_ids: fixture["requirements"]
    @tag vector_id: fixture["id"]
    test "#{fixture["id"]} executes #{fixture["operation"]} against the exact declared projection" do
      fixture = unquote(Macro.escape(fixture))
      operation = Map.fetch!(@operations, fixture["operation"])
      bytes = Base.decode16!(fixture["input"]["binary_hex"], case: :lower)
      result = apply(Binary, operation, [bytes])
      assert project_result(result) == fixture["expectation"]["value"]
    end
  end

  defp project_result({:ok, value, tail}),
    do: %{"ok" => project(value), "tail_hex" => Base.encode16(tail, case: :lower)}

  defp project_result({:error, %Error{code: code, effect: effect}}),
    do: %{"error" => %{"code" => Atom.to_string(code), "effect" => Atom.to_string(effect)}}

  defp project(%Address{} = value), do: Address.to_string(value)

  defp project(%{type: type} = value) when type in ["ByteString", "Reserved"] do
    Map.new(value, fn
      {:value, bytes} -> {"value", project_bytes(bytes)}
      {key, value} -> {Atom.to_string(key), project(value)}
    end)
  end

  defp project(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {Atom.to_string(key), project(value)} end)

  defp project(value) when is_list(value), do: Enum.map(value, &project/1)
  defp project(value), do: value

  defp project_bytes(nil), do: nil

  defp project_bytes(bytes) when is_binary(bytes),
    do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}

  defp project_bytes(values) when is_list(values), do: Enum.map(values, &project_bytes/1)
end
