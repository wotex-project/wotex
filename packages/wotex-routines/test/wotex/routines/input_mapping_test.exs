defmodule Wotex.Routines.InputMappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Error, Input, InputMapping}
  alias Wotex.Routines.InputFixtures, as: F

  test "selected mappings revalidate installation, native shape and aggregate limits" do
    v = F.vector()
    assert {:ok, mapping} = InputMapping.new(v["mapping"], v["registry"], v["limits"])
    assert {:ok, data} = InputMapping.to_map(mapping, v["registry"], v["limits"])
    assert data == v["mapping"]
    assert {:ok, [^mapping]} = InputMapping.new_all([data], v["registry"], v["limits"])
    assert {:ok, []} = InputMapping.new_all([], v["registry"], v["limits"])

    assert {:error, %Error{code: :unsupported_mapping}} =
             InputMapping.new_all([data, data], v["registry"], v["limits"])

    assert {:error, %Error{code: :input_limit}} =
             InputMapping.new_all(List.duplicate(data, 257), v["registry"], v["limits"])

    for input <- [nil, %{}, [%{}], [mapping]] do
      assert {:error, %Error{}} = InputMapping.new_all(input, v["registry"], v["limits"])
    end

    for bad <- [
          Map.put(mapping, :foreign, "secret-canary"),
          Map.put(data, "private-canary", "secret-canary"),
          %URI{},
          Map.delete(data, "sha256"),
          Map.put(data, "sha256", "bad"),
          Map.put(data, "sha256", String.duplicate("0", 64))
        ] do
      assert {:error, %Error{} = error} = InputMapping.new(bad, v["registry"], v["limits"])
      refute inspect(error) =~ "canary"
    end

    missing = Enum.reject(v["registry"], &(&1["id"] == data["correspondence_ref"]["id"]))

    assert {:error, %Error{code: :unsupported_mapping}} =
             InputMapping.new(data, missing, v["limits"])
  end

  test "different dimensions and unqualified projections cannot relabel sensor data" do
    v = F.vector()
    unsigned = Map.delete(v["mapping"], "sha256")

    for dimension <- [[-1, 1, -2, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]] do
      assert {:error, %Error{code: :incompatible_dimension}} =
               InputMapping.digest(
                 put_in(unsigned, ["external_unit", "dimension"], dimension),
                 v["registry"],
                 v["limits"]
               )
    end

    for {path, value} <- [
          {~w(id), "relative"},
          {~w(version), "01.0.0"},
          {~w(version), "65536.0.0"},
          {~w(channel_id), "route/secret-canary"},
          {~w(affordance), %{}},
          {~w(affordance kind), "action"},
          {~w(affordance name), "other"},
          {~w(projection), "float"},
          {~w(enum_table), []},
          {~w(external_unit quantity_kind), "relative"},
          {~w(external_unit dimension), [0]},
          {~w(external_unit dimension), [0, 0, 0, 0, 33, 0, 0]},
          {~w(external_unit scale_d), "0"},
          {~w(external_unit scale_n), "-1"},
          {~w(external_unit offset_n), "27315"},
          {~w(external_unit scale_n), "9223372036854775808"},
          {~w(observation), nil},
          {~w(observation source_ref), ""},
          {~w(observation source_epoch), "bad"},
          {~w(observation source_class), "other"},
          {~w(observation source_time_basis), "bad"},
          {~w(receipt_clock source_epoch), "bad"},
          {~w(receipt_clock source_origin_us), "01"},
          {~w(receipt_clock source_origin_us), "9223372036854775808"},
          {~w(receipt_clock target_epoch), ""},
          {~w(receipt_clock target_origin_ms), -1},
          {~w(reader_contract_ref sha256), String.duplicate("0", 64)},
          {~w(legacy_basis_ref semantic_digest), "sha256:" <> String.duplicate("0", 64)},
          {~w(compiler_ref), %{}},
          {~w(semantic_ref id), "urn:example:other\u0000"}
        ] do
      assert {:error, %Error{} = error} =
               InputMapping.digest(
                 put_in(unsigned, Enum.map(path, &Access.key!(&1)), value),
                 v["registry"],
                 v["limits"]
               )

      refute inspect(error) =~ "canary"
    end
  end

  test "boolean correspondence uses the installed exact type" do
    v = F.vector()
    unsigned = Map.delete(v["mapping"], "sha256")
    value = %{"type" => "boolean", "unit" => nil, "enum" => []}

    unsigned =
      unsigned
      |> Map.merge(%{"projection" => "boolean", "external_unit" => nil})
      |> put_in(["basis", "value"], value)
      |> put_in(["basis", "output"], value)

    v = F.install(v, unsigned)

    proposal =
      Map.merge(v["proposal"], %{
        "unit" => nil,
        "normalized_value" => %{"type" => "boolean", "value" => false}
      })

    assert {:ok, result} = Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
    assert result["fact"].data["value"] == false
    assert result["fact"].data["unit"] == nil

    assert {:error, %Error{code: :unsupported_representation}} =
             Input.project(
               Map.put(proposal, "normalized_value", %{"type" => "sint", "value" => "0"}),
               v["mapping"],
               v["metadata"],
               F.context(v)
             )
  end

  test "a valid installed write or effect-bearing basis cannot become an input mapping" do
    v = F.vector()

    for {path, value} <- [
          {~w(basis affordance operation), "writeproperty"},
          {~w(basis effects resource_roles), ["actuator"]},
          {~w(observation source_class), "protocol_response"}
        ] do
      unsigned = put_in(Map.delete(v["mapping"], "sha256"), Enum.map(path, &Access.key!(&1)), value)
      {unsigned, registry} = F.prepare(v, unsigned)

      assert {:error, %Error{code: :unsupported_mapping}} =
               InputMapping.digest(unsigned, registry, v["limits"])
    end
  end

  test "enum correspondence is complete, bijective and has no unmatched default" do
    v = F.vector()
    value = %{"type" => "enum", "unit" => nil, "enum" => ["closed", "open"]}
    entries = [%{"source" => "0", "target" => "closed"}, %{"source" => "1", "target" => "open"}]

    unsigned =
      v["mapping"]
      |> Map.delete("sha256")
      |> Map.merge(%{"projection" => "enum", "external_unit" => nil, "enum_table" => entries})
      |> put_in(["basis", "value"], value)
      |> put_in(["basis", "output"], value)

    v = F.install(v, unsigned)

    proposal =
      Map.merge(v["proposal"], %{
        "unit" => nil,
        "normalized_value" => %{"type" => "text", "value" => "1"}
      })

    assert {:ok, result} = Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
    assert result["fact"].data["value"] == "open"

    for node <- [%{"type" => "text", "value" => "other"}, %{"type" => "sint", "value" => "1"}] do
      assert {:error, %Error{code: :unsupported_representation}} =
               Input.project(
                 Map.put(proposal, "normalized_value", node),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )
    end

    unsigned = Map.delete(v["mapping"], "sha256")

    for bad <- [
          nil,
          [],
          Enum.reverse(entries),
          [hd(entries)],
          [hd(entries), hd(entries)],
          [%{"source" => "0", "target" => "open"}, %{"source" => "1", "target" => "open"}],
          [%{}],
          [%{"source" => "", "target" => "open"}],
          [%{"source" => "0", "target" => String.duplicate("x", 129)}]
        ] do
      assert {:error, %Error{code: :unsupported_mapping}} =
               InputMapping.digest(Map.put(unsigned, "enum_table", bad), v["registry"], v["limits"])
    end
  end
end
