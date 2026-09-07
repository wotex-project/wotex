defmodule WotexContinuum.PropertyContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias WotexContinuum.{CanonicalJSON, Codec, Error, Limits}

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

  test "post-decode limits reject oversized nested values with exact paths" do
    limits = %Limits{Limits.defaults() | max_collection_size: 1, max_string_bytes: 2, max_depth: 1}

    assert {:error, %Error{code: :limit_exceeded}} =
             Limits.normalize_decoded([1, 2], limits)

    assert {:error, %Error{code: :limit_exceeded}} =
             Limits.normalize_decoded("long", limits)

    ordered = %Jason.OrderedObject{values: [{"a", %Jason.OrderedObject{values: [{"b", true}]}}]}

    assert {:error, %Error{code: :limit_exceeded, path: "/a/b"}} =
             Limits.normalize_decoded(ordered, limits)

    assert {:error, %Error{code: :invalid_type}} = Limits.new(:invalid)
  end

  test "source scanning accounts for escaped string bytes" do
    source =
      ~s({"kind":"mode","schema_version":"1.0.0","deployment":"saas","connectivity":"connected","extensions":{"https://example.org/text":"a\\nb"}})

    assert {:ok, _} = Codec.decode(source, max_string_bytes: 128)
  end

  defp stringify_integer_keys(value) do
    Map.new(value, fn {key, item} -> {key, stringify_json(item)} end)
  end

  defp stringify_json(items) when is_list(items), do: Enum.map(items, &stringify_json/1)
  defp stringify_json(value), do: value
end
