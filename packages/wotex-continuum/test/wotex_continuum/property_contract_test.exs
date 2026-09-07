defmodule WotexContinuum.PropertyContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias WotexContinuum.{CanonicalJSON, Codec, Error, Limits, Validation}

  property "canonical JSON is deterministic and decodes to the original JSON value" do
    json_scalar = one_of([constant(nil), boolean(), integer(), string(:alphanumeric)])

    check all(
            value <-
              map_of(
                string(:alphanumeric, min_length: 1, max_length: 12),
                one_of([json_scalar, list_of(json_scalar, max_length: 8)]),
                max_length: 12
              )
          ) do
      assert {:ok, first} = CanonicalJSON.encode(value)
      assert {:ok, second} = CanonicalJSON.encode(value)
      assert first == second
      assert Jason.decode!(first) == stringify_integer_keys(value)
    end
  end

  test "every registered vector preserves its value module contract" do
    vector_root = Path.expand("../vectors/valid", __DIR__)

    for path <- Path.wildcard(Path.join(vector_root, "*.json")) do
      input =
        path
        |> File.read!()
        |> Jason.decode!()

      assert {:ok, value} = WotexContinuum.from_map(input), path

      module = value.__struct__
      assert module.kind() == input["kind"], path
      assert {:ok, ^value} = module.new(value), path
    end
  end

  test "delegated admission reports limit breaches with exact pointer paths" do
    source = ~s({"kind":"mode","extensions":{"https://example.org/a":{"b":1,"c":2,"d":3}}})
    nested = "/extensions/https:~1~1example.org~1a"

    assert {:error, %Error{code: :limit_exceeded, phase: :limits, path: ^nested} = error} =
             Codec.decode(source, max_collection_size: 2)

    assert error.details.core_code == :collection_limit_exceeded

    assert {:error, %Error{code: :limit_exceeded, phase: :limits, path: ^nested}} =
             Codec.decode(source, max_nodes: 3)

    assert {:error, %Error{code: :limit_exceeded, phase: :limits, path: "/"}} =
             Codec.decode(source, max_string_bytes: 2)

    assert {:error, %Error{code: :invalid_type, phase: :limits}} = Limits.new(:invalid)
    assert {:ok, %Limits{max_nodes: 5}} = Limits.new(%{max_nodes: 5})
  end

  test "one nesting bound applies to decoded source and native JSON values" do
    depth = Limits.max_depth()
    assert depth == Limits.defaults().max_depth

    accepted = nested_lists(depth)
    rejected = nested_lists(depth + 1)

    assert {:ok, ^accepted} = Validation.json_value(accepted, Error.root())

    assert {:error, %Error{code: :limit_exceeded, phase: :limits}} =
             Validation.json_value(rejected, Error.root())

    assert {:ok, _} = Codec.decode(mode_source(depth - 2))
    assert {:error, %Error{code: :limit_exceeded}} = Codec.decode(mode_source(depth))
  end

  test "source scanning accounts for escaped string bytes" do
    source =
      ~s({"kind":"mode","schema_version":"1.0.0","deployment":"saas","connectivity":"connected","extensions":{"https://example.org/text":"a\\nb"}})

    assert {:ok, _} = Codec.decode(source, max_string_bytes: 128)
  end

  defp nested_lists(levels), do: Enum.reduce(1..levels, nil, fn _, acc -> [acc] end)

  defp mode_source(levels) do
    payload = Enum.reduce(1..levels, "true", fn _, acc -> "[" <> acc <> "]" end)

    ~s({"kind":"mode","schema_version":"1.0.0","deployment":"saas","connectivity":"connected",) <>
      ~s("extensions":{"https://example.org/deep":) <> payload <> "}}"
  end

  defp stringify_integer_keys(value) do
    Map.new(value, fn {key, item} -> {key, stringify_json(item)} end)
  end

  defp stringify_json(items) when is_list(items), do: Enum.map(items, &stringify_json/1)
  defp stringify_json(value), do: value
end
