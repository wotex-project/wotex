defmodule Wotex.JSONDepthTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{ActionAffordance, DataSchema, Error, EventAffordance, Form, JSON}
  alias Wotex.{PropertyAffordance, SecurityScheme, ThingDescription, ThingModel}

  test "root scalars add no container depth and string brackets remain ordinary text" do
    for value <- [nil, false, true, 0, -1, 1.5, "\"[{}]𝄞\""] do
      assert :ok == JSON.validate(value, max_depth: 1)
      assert {:ok, bytes} = JSON.encode(value, max_depth: 1)
      assert {:ok, ^value} = JSON.decode(bytes, max_depth: 1)
    end
  end

  test "empty and scalar leaves have equal native and source container-depth boundaries" do
    for kind <- [:object, :array, :mixed],
        levels <- 0..8,
        leaf <- [%{}, [], 0, "[not a container]"] do
      {value, segments} = chain(leaf, levels, kind)
      required = levels + if(is_map(leaf) or is_list(leaf), do: 1, else: 0)
      selected = max(1, required)
      source = Jason.encode!(value)
      assert {:ok, ^value} = JSON.decode(source, max_depth: selected)
      assert :ok == JSON.validate(value, max_depth: selected)
      assert {:ok, encoded} = JSON.encode(value, max_depth: selected)
      assert {:ok, ^value} = JSON.decode(encoded, max_depth: selected)

      if required > 1 do
        limit = required - 1
        path = "/" <> Enum.join(Enum.take(segments, limit), "/")

        assert {:error, %Error{code: :depth_limit_exceeded, phase: :parse}} =
                 JSON.decode(source, max_depth: limit)

        expected = %Error{
          code: :depth_limit_exceeded,
          phase: :value,
          path: path,
          message: "JSON value exceeds the configured nesting depth",
          details: %{max_depth: limit}
        }

        assert {:error, ^expected} = JSON.validate(value, max_depth: limit)
        assert {:error, ^expected} = JSON.encode(value, max_depth: limit)
      end
    end
  end

  test "siblings use maximum container depth and errors identify the overflowing container" do
    value = %{"empty object" => %{}, "empty array" => [], "n/e~" => [%{"leaf" => %{}}]}
    source = Jason.encode!(value)
    assert :ok == JSON.validate(value, max_depth: 4)
    assert {:ok, ^value} = JSON.decode(source, max_depth: 4)

    for {selected, path} <- [{2, "/n~1e~0/0"}, {3, "/n~1e~0/0/leaf"}] do
      assert {:error, %Error{code: :depth_limit_exceeded, phase: :value, path: ^path}} =
               JSON.validate(value, max_depth: selected)

      assert {:error, %Error{code: :depth_limit_exceeded, phase: :value, path: ^path}} =
               JSON.encode(value, max_depth: selected)

      assert {:error, %Error{code: :depth_limit_exceeded, phase: :parse}} =
               JSON.decode(source, max_depth: selected)
    end
  end

  test "the default sixty-four containers and an explicitly raised depth agree in both forms" do
    {exact, _} = chain([], 63, :array)
    {over, _} = chain([], 64, :array)
    assert :ok == JSON.validate(exact)
    assert {:ok, bytes} = JSON.encode(exact)
    assert {:ok, ^exact} = JSON.decode(bytes)
    assert {:error, %Error{code: :depth_limit_exceeded}} = JSON.validate(over)
    assert {:error, %Error{code: :depth_limit_exceeded}} = JSON.encode(over)
    assert {:error, %Error{code: :depth_limit_exceeded}} = JSON.decode(Jason.encode!(over))
    assert :ok == JSON.validate(over, max_depth: 65)
    assert {:ok, bytes} = JSON.encode(over, max_depth: 65)
    assert {:ok, ^over} = JSON.decode(bytes, max_depth: 65)
  end

  test "aggregate and value constructors count the final empty extension container" do
    extension = [%{"nest" => [%{}]}]
    expected_path = "/x-depth/0/nest/0"

    for {constructor, projector, document} <- boundaries() do
      document = Map.put(document, "x-depth", extension)
      assert {:ok, value} = constructor.(document, max_depth: 5)
      assert projector.(value) == document

      for opts <- [[max_depth: 4], [max_depth: 4, validate: false]] do
        assert {:error, %Error{code: :depth_limit_exceeded, phase: :value, path: ^expected_path}} =
                 constructor.(document, opts)
      end
    end

    for {module, base} <- aggregates() do
      document = Map.put(base, "x-depth", extension)
      bytes = Jason.encode!(document)
      assert {:ok, value} = module.parse(bytes, max_depth: 5)
      assert module.to_map(value) == document

      for opts <- [[max_depth: 4], [max_depth: 4, validate: false]] do
        assert {:error, %Error{code: :depth_limit_exceeded, phase: :parse}} =
                 module.parse(bytes, opts)

        assert {:error, %Error{code: :depth_limit_exceeded, path: ^expected_path}} =
                 module.put_id(value, "urn:example:changed", opts)
      end
    end
  end

  defp chain(leaf, count, kind) do
    kinds =
      List.duplicate(kind, count)
      |> Enum.with_index()
      |> Enum.map(fn
        {:mixed, i} -> if rem(i, 2) == 0, do: :object, else: :array
        {selected, _} -> selected
      end)

    value =
      Enum.reduce(kinds, leaf, fn
        :object, value -> %{"branch/key~" => value}
        :array, value -> [value]
      end)

    segments =
      kinds
      |> Enum.reverse()
      |> Enum.map(fn
        :object -> "branch~1key~0"
        :array -> "0"
      end)

    {value, segments}
  end

  defp aggregates do
    [
      {ThingDescription,
       %{
         "@context" => Wotex.td_context_1_1(),
         "title" => "Depth example",
         "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
         "security" => ["none"]
       }},
      {ThingModel,
       %{
         "@context" => Wotex.td_context_1_1(),
         "@type" => "tm:ThingModel",
         "title" => "Depth model"
       }}
    ]
  end

  defp boundaries do
    Enum.map(aggregates(), fn {module, document} ->
      {&module.from_map/2, &module.to_map/1, document}
    end) ++
      [
        {&DataSchema.new/2, &DataSchema.to_map/1, %{"type" => "number"}},
        {&Form.new/2, &Form.to_map/1, %{"href" => "relative"}},
        {&PropertyAffordance.new/2, &PropertyAffordance.to_map/1,
         %{"forms" => [%{"href" => "relative"}]}},
        {&ActionAffordance.new/2, &ActionAffordance.to_map/1,
         %{"forms" => [%{"href" => "relative"}]}},
        {&EventAffordance.new/2, &EventAffordance.to_map/1,
         %{"forms" => [%{"href" => "relative"}]}},
        {&SecurityScheme.new/2, &SecurityScheme.to_map/1, %{"scheme" => "nosec"}}
      ]
  end
end
