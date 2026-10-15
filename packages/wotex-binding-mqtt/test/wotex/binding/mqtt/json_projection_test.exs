defmodule Wotex.Binding.MQTT.JSONProjectionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Binding.MQTT.{Delivery, Error, JSONProjection}
  alias Wotex.Runtime.Codec.Value

  doctest JSONProjection

  @vectors __DIR__
           |> Path.join("../../../support/json_projection_vectors.json")
           |> File.read!()
           |> Jason.decode!()

  test "all independent literal payloads preserve exact values and delivery metadata" do
    for row <- @vectors["cases"] do
      {:ok, delivery} =
        Delivery.new(row["payload"], topic: row["topic"], qos: row["qos"], retain: row["retain"])

      result = JSONProjection.project(delivery, row["selector"])

      cond do
        row["ignore"] ->
          assert result == :ignore, row["id"]

        row["error"] ->
          assert {:error, %Error{code: code, details: %{}}} = result
          assert Atom.to_string(code) == row["error"], row["id"]

        true ->
          assert {:ok, value, metadata} = result
          assert value == row["expected"], row["id"]
          assert {:ok, ^value} = Value.validate(value)
          assert metadata == %{topic: row["topic"], qos: row["qos"], retained: row["retain"]}
      end
    end
  end

  test "closed semantic selector rejects structs, forged fields, improper lists and UTF-8 excess" do
    for selector <- [
          nil,
          [],
          %{},
          %{topic: "a", path: []},
          MapSet.new(),
          %{"topic" => "a", "path" => [], "private-canary" => true},
          selection("a", ["x" | :bad]),
          selection("a", List.duplicate("x", 8)),
          selection("a", [0]),
          selection("a", [<<255>>]),
          selection("a", [String.duplicate("é", 65)]),
          selection(""),
          selection("a/+"),
          selection("a/#"),
          selection("a\0b"),
          selection(<<255>>),
          selection(String.duplicate("é", 513))
        ] do
      assert {:error,
              %Error{
                code: :invalid_profile_selector,
                phase: :mapping,
                class: :permanent,
                details: %{}
              } = error} =
               JSONProjection.validate_selector(selector)

      refute inspect(error) =~ "private-canary"
      assert {:error, ^error} = JSONProjection.project(:bad, selector)
    end

    assert :ok =
             JSONProjection.validate_selector(
               selection(String.duplicate("é", 512), [String.duplicate("é", 64)])
             )

    assert :ok = JSONProjection.validate_selector(selection("a", ["", "a/b", "~1", "01"]))
  end

  test "delivery is reconstructed without coercion, forged or missing fields" do
    {:ok, delivery} = Delivery.new("null", topic: "a")

    for bad <- [
          nil,
          %{},
          Map.from_struct(delivery),
          Map.put(delivery, :extra, "private-canary"),
          Map.put(delivery, :qos, "0"),
          Map.put(delivery, :retain, nil),
          Map.put(delivery, :payload, 3),
          Map.put(delivery, :topic, "a/#"),
          Map.put(delivery, :topic, <<255>>),
          Map.put(Map.delete(delivery, :payload), :extra, "private-canary")
        ] do
      assert {:error,
              %Error{code: :invalid_delivery, phase: :client, class: :protocol, details: %{}} =
                error} =
               JSONProjection.project(bad, selection("a"))

      refute inspect(error) =~ "private-canary"
    end
  end

  test "topic equality precedes decoding but follows the fixed payload ceiling" do
    assert :ignore = project("private-canary invalid", selection("a"), "b")
    assert :ignore = project(<<255>>, selection("a"), "b")
    assert :ignore = project("", selection("a"), "b")

    assert {:ok, %{"type" => "sint", "value" => "1"}, _} =
             project("1" <> String.duplicate(" ", 65_535), selection("a"))

    for topic <- ["a", "b"] do
      assert {:error, %Error{code: :json_output_limit, phase: :codec, class: :protocol}} =
               project(String.duplicate(" ", 65_537), selection("a"), topic)
    end

    assert {:error, %Error{code: :json_invalid_input}} = project("", selection("a"))
    assert :ignore = project("1", selection("é"), "é")
  end

  test "bounded paths preserve root, deepest child, literal keys and canonical array indices" do
    deepest = Enum.reduce(1..7, "false", fn _, inner -> ~s({"a":#{inner}}) end)

    assert {:ok, %{"type" => "boolean", "value" => false}, _} =
             project(deepest, selection("a", List.duplicate("a", 7)))

    array = Jason.encode!(Enum.to_list(0..255))
    assert {:ok, %{"value" => "0"}, _} = project(array, selection("a", ["0"]))
    assert {:ok, %{"value" => "255"}, _} = project(array, selection("a", ["255"]))

    for key <- [
          "256",
          "999",
          "000",
          "00",
          "-0",
          "+0",
          "1.0",
          "1e0",
          "-",
          String.duplicate("9", 128)
        ] do
      assert {:error, %Error{code: :profile_value_missing}} = project(array, selection("a", [key]))
    end

    for {input, path} <- [{"{}", [""]}, {"false", ["a"]}, {"{\"a\":null}", ["missing"]}] do
      assert {:error, %Error{code: :profile_value_missing}} = project(input, selection("a", path))
    end

    assert {:ok, %{"type" => "null"}, _} = project(~s({"a":null}), selection("a", ["a"]))
  end

  test "full payload validation refuses unselected duplicate, invalid and excessive data" do
    for {input, code} <- [
          {~s({"a":1,"b":{"x":0,"x":1}}), :json_invalid_input},
          {~s({"a":1,"b":1e32768}), :json_unsupported_value},
          {~s({"a":1,"b":") <> String.duplicate("x", 4097) <> ~s("}), :json_output_limit}
        ] do
      assert {:error, %Error{code: ^code, details: %{}} = error} =
               project(input, selection("a", ["a"]))

      refute inspect(error) =~ "private-canary"
    end
  end

  test "explicit independent processes repeat the same exact projection" do
    input = ~s({"a":9007199254740993.1})
    selector = selection("a", ["a"])
    expected = project(input, selector)
    assert {:ok, _, _} = expected

    results = Task.async_stream(1..16, fn _ -> project(input, selector) end, max_concurrency: 4)
    for result <- results, do: assert(result == {:ok, expected})
  end

  defp selection(topic, path \\ []), do: %{"topic" => topic, "path" => path}

  defp project(payload, selector, topic \\ "a") do
    {:ok, delivery} = Delivery.new(payload, topic: topic)
    JSONProjection.project(delivery, selector)
  end
end
