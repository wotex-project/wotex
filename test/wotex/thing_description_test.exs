defmodule Wotex.ThingDescriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{Error, ThingDescription}

  test "schema violations retain the failing field path without copying its value" do
    sentinel = %{"credential-sentinel" => "must-not-appear"}
    assert {:error, errors} = ThingDescription.from_map(Map.put(valid_td_map(), "title", sentinel))
    assert Enum.any?(errors, &(&1.code == :schema_violation and &1.path == "/title"))
    refute inspect(errors) =~ "credential-sentinel"
    refute inspect(errors) =~ "must-not-appear"
  end

  test "parses TD 1.1 JSON and preserves original source bytes" do
    json = Jason.encode!(valid_td_map())

    assert {:ok, td} = ThingDescription.parse(json)
    assert ThingDescription.id(td) == "urn:example:sensor:1"
    assert ThingDescription.to_map(td)["x-example:calibration"] == %{"offset" => 0.25}
    assert {:ok, ^json} = ThingDescription.encode(td, :source)
  end

  test "canonical encoding is independent of map insertion order" do
    first = valid_td_map()

    second =
      first
      |> Enum.reverse()
      |> Map.new()
      |> Map.update!("properties", fn properties ->
        reversed = Enum.reverse(properties)
        Map.new(reversed)
      end)

    assert {:ok, first_td} = ThingDescription.from_map(first)
    assert {:ok, second_td} = ThingDescription.from_map(second)
    assert {:ok, first_json} = ThingDescription.encode(first_td, :canonical)
    assert {:ok, second_json} = ThingDescription.encode(second_td, :canonical)
    assert first_json == second_json
    assert Jason.decode!(first_json) == first
  end

  test "rejects invalid UTF-8 in native-map extension keys and values" do
    for extension <- [%{"x-example:label" => <<255>>}, %{<<255>> => "label"}] do
      assert {:error, %Error{code: :invalid_string}} =
               valid_td_map()
               |> Map.merge(extension)
               |> ThingDescription.from_map()
    end
  end

  test "encoding a forged TD containing invalid UTF-8 returns structured errors" do
    unsafe = %ThingDescription{document: Map.put(valid_td_map(), "x-example:label", <<255>>)}

    assert {:error, %Error{code: :invalid_string, phase: :value}} =
             ThingDescription.encode(unsafe, :canonical)

    assert {:error, %Error{code: :encode_failed, phase: :encode}} =
             ThingDescription.encode(unsafe, :compact)
  end

  test "mutation validates the result and invalidates source-byte encoding" do
    json = Jason.encode!(valid_td_map())
    assert {:ok, td} = ThingDescription.parse(json)
    assert {:ok, changed} = ThingDescription.put_id(td, "urn:example:sensor:2")
    assert ThingDescription.id(changed) == "urn:example:sensor:2"

    assert {:error, %Error{code: :source_unavailable, phase: :encode}} =
             ThingDescription.encode(changed, :source)
  end

  test "rejects a legacy context as a production TD 1.1 claim" do
    map = Map.put(valid_td_map(), "@context", "https://www.w3.org/2019/wot/td/v1")

    assert {:error, errors} = ThingDescription.from_map(map)
    assert Enum.any?(errors, &(&1.code == :unsupported_context and &1.path == "/@context"))
  end

  test "returns a typed malformed JSON error" do
    assert {:error, %Error{code: :invalid_json, phase: :parse}} =
             ThingDescription.parse(~s({"title":))
  end

  test "parse rejects non-binary input and raising variants reuse structured errors" do
    assert {:error, %Error{code: :invalid_input}} = ThingDescription.parse(%{})

    json = Jason.encode!(valid_td_map())
    assert %ThingDescription{} = ThingDescription.parse!(json)

    assert_raise Error, fn -> ThingDescription.parse!(~s({"title":)) end

    legacy =
      valid_td_map()
      |> Map.put("@context", "https://www.w3.org/2019/wot/td/v1")
      |> Jason.encode!()

    assert_raise Error, fn -> ThingDescription.parse!(legacy) end
  end

  test "requires a JSON object root" do
    assert {:error, %Error{code: :object_required, path: "/"}} =
             ThingDescription.parse(~s(["not", "a", "td"]))
  end

  test "enforces byte limits before decoding" do
    json = Jason.encode!(valid_td_map())

    assert {:error, %Error{code: :byte_limit_exceeded, details: %{max_bytes: 8}}} =
             ThingDescription.parse(json, max_bytes: 8)
  end

  test "enforces depth and node limits for map input" do
    deep =
      put_in(valid_td_map(), ["x-example:deep"], %{"a" => %{"b" => %{"c" => true}}})

    assert {:error, %Error{code: :depth_limit_exceeded}} =
             ThingDescription.from_map(deep, max_depth: 2)

    assert {:error, %Error{code: :node_limit_exceeded}} =
             ThingDescription.from_map(valid_td_map(), max_nodes: 3)
  end

  test "rejects non-string JSON object keys" do
    map = Map.put(valid_td_map(), :private_key, true)

    assert {:error, %Error{code: :non_string_key}} = ThingDescription.from_map(map)
  end

  test "reports pinned schema provenance" do
    assert %{
             standard: "W3C WoT Thing Description 1.1",
             recommendation_date: "2023-12-05",
             upstream_tag: "REC1.1",
             upstream_commit: "7c0b968f403ecdb9594bd882cafbacf544c41fc0",
             sha256: "87481cfafa3847d0c593c047750e090d4365dcc0f1b5daab3a725d63c991a4da",
             informative: true
           } = ThingDescription.schema_info()
  end

  test "supports explicit validation and source-free compact and pretty encodings" do
    assert {:ok, td} = ThingDescription.from_map(valid_td_map(), validate: false)
    assert {:ok, ^td} = ThingDescription.validate(td)
    assert {:ok, compact} = ThingDescription.encode(td, :compact)
    assert {:ok, pretty} = ThingDescription.encode(td, :pretty)
    assert Jason.decode!(compact) == valid_td_map()
    assert Jason.decode!(pretty) == valid_td_map()
    assert String.contains?(pretty, "\n")

    assert {:error, %Error{code: :source_unavailable}} = ThingDescription.encode(td, :source)
    assert {:error, %Error{code: :unsupported_encoding}} = ThingDescription.encode(td, :xml)
  end

  test "rejects invalid identifiers and propagates validation after mutation" do
    assert {:ok, td} = ThingDescription.from_map(valid_td_map())
    assert {:error, %Error{code: :invalid_id, path: "/id"}} = ThingDescription.put_id(td, "")

    assert {:ok, invalid} = ThingDescription.from_map(%{"title" => "incomplete"}, validate: false)
    assert {:error, errors} = ThingDescription.put_id(invalid, "urn:example:incomplete")
    assert errors != []
  end

  test "accepts the TD 1.1 context in an extension context array" do
    map =
      Map.put(valid_td_map(), "@context", [
        Wotex.td_context_1_1(),
        %{"x-example" => "https://example.test/vocabulary#"}
      ])

    assert {:ok, _td} = ThingDescription.from_map(map)
  end

  test "rejects a context array without the TD 1.1 context and an empty title" do
    map =
      valid_td_map()
      |> Map.put("@context", ["https://example.test/context"])
      |> Map.put("title", "   ")

    assert {:error, errors} = ThingDescription.from_map(map)
    assert Enum.any?(errors, &(&1.code == :unsupported_context))
    assert Enum.any?(errors, &(&1.code == :empty_title))
  end

  test "schema failures carry a schema phase and normalized path" do
    invalid = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Invalid",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "properties" => %{"temperature" => %{"forms" => [%{"op" => "readproperty"}]}}
    }

    assert {:error, errors} = ThingDescription.from_map(invalid)
    assert Enum.any?(errors, &(&1.phase == :schema and String.starts_with?(&1.path, "/")))
  end

  test "rejects undefined Thing and Form security references with stable paths" do
    invalid =
      valid_td_map()
      |> Map.put("security", ["missing_root"])
      |> put_in(
        ["properties"],
        %{
          "sensor/level~raw" => %{
            "type" => "number",
            "forms" => [
              %{"href" => "https://example.test/level", "security" => ["missing_form"]}
            ]
          }
        }
      )

    assert {:error, errors} = ThingDescription.from_map(invalid)

    assert Enum.any?(
             errors,
             &(&1.code == :undefined_security_reference and &1.phase == :semantic and
                 &1.path == "/security/0" and &1.details == %{reference: "missing_root"})
           )

    assert Enum.any?(
             errors,
             &(&1.code == :undefined_security_reference and &1.phase == :semantic and
                 &1.path == "/properties/sensor~1level~0raw/forms/0/security/0" and
                 &1.details == %{reference: "missing_form"})
           )
  end

  test "rejects undefined ComboSecurityScheme references" do
    invalid =
      valid_td_map()
      |> put_in(
        ["securityDefinitions", "combo_sc"],
        %{"scheme" => "combo", "oneOf" => ["nosec_sc", "missing_sc"]}
      )
      |> Map.put("security", ["combo_sc"])

    assert {:error, errors} = ThingDescription.from_map(invalid)

    assert Enum.any?(
             errors,
             &(&1.code == :undefined_security_reference and
                 &1.path == "/securityDefinitions/combo_sc/oneOf/1" and
                 &1.details == %{reference: "missing_sc"})
           )
  end

  test "explicit validation retains semantic errors for non-string titles" do
    map = Map.put(valid_td_map(), "title", 42)
    assert {:ok, td} = ThingDescription.from_map(map, validate: false)
    assert {:error, errors} = ThingDescription.validate(td, [])
    assert Enum.any?(errors, &(&1.phase == :schema))
  end

  test "invalid limit options are rejected instead of silently replaced" do
    json = Jason.encode!(valid_td_map())

    assert {:error, %Error{code: :invalid_limit, details: %{option: :max_bytes}}} =
             ThingDescription.parse(json, max_bytes: 0)

    assert {:error, %Error{code: :invalid_limit, details: %{option: :max_nodes}}} =
             ThingDescription.from_map(valid_td_map(), max_nodes: "many")
  end

  test "requires the TD 1.1 context first, optionally after the TD 1.0 context" do
    v1_1 = Wotex.td_context_1_1()
    v1 = "https://www.w3.org/2019/wot/td/v1"

    assert {:ok, _td} = ThingDescription.from_map(Map.put(valid_td_map(), "@context", [v1, v1_1]))

    assert {:ok, _td} =
             ThingDescription.from_map(
               Map.put(valid_td_map(), "@context", [v1_1, "https://example.test/context"])
             )

    vendor_first = Map.put(valid_td_map(), "@context", ["https://example.test/context", v1_1])
    assert {:error, errors} = ThingDescription.from_map(vendor_first)
    assert Enum.any?(errors, &(&1.code == :unsupported_context and &1.path == "/@context"))
  end

  test "rejects a Thing Model as a Thing Description with a dedicated code" do
    assert {:error, errors} =
             ThingDescription.from_map(Map.put(valid_td_map(), "@type", ["Thing", "tm:ThingModel"]))

    assert Enum.any?(errors, &(&1.code == :thing_model_not_accepted and &1.path == "/@type"))
  end

  test "rejects duplicate members and bounds strings and payload during parsing" do
    duplicated = ~s({"@context":"#{Wotex.td_context_1_1()}","title":"a","title":"b"})

    assert {:error, %Error{code: :duplicate_member, path: "/title"}} =
             ThingDescription.parse(duplicated)

    json = Jason.encode!(valid_td_map())

    assert {:error, %Error{code: :string_limit_exceeded}} =
             ThingDescription.parse(json, max_string_bytes: 8)

    assert {:error, %Error{code: :object_required}} = ThingDescription.parse("[]")
    assert {:error, %Error{code: :object_required}} = ThingDescription.from_map("x")

    assert {:error, %Error{code: :byte_limit_exceeded, phase: :value}} =
             ThingDescription.from_map(valid_td_map(), max_bytes: 16)
  end

  test "applies TD 1.1 default operations to affordance Forms without op" do
    map =
      valid_td_map()
      |> put_in(["properties", "temperature", "forms"], [%{"href" => "https://example.test/t"}])
      |> Map.put("actions", %{
        "reset" => %{"forms" => [%{"href" => "https://example.test/reset"}]}
      })
      |> Map.put("events", %{
        "alarm" => %{"forms" => [%{"href" => "https://example.test/alarm"}]}
      })

    assert {:ok, td} = ThingDescription.from_map(map)
    document = ThingDescription.to_map(td)

    assert {:ok, property} = Wotex.PropertyAffordance.new(document["properties"]["temperature"])
    assert {:ok, [form]} = Wotex.PropertyAffordance.forms(property)
    assert Wotex.PropertyAffordance.operations(property, form) == ["readproperty"]

    assert {:ok, action} = Wotex.ActionAffordance.new(document["actions"]["reset"])
    assert {:ok, [form]} = Wotex.ActionAffordance.forms(action)
    assert Wotex.ActionAffordance.operations(action, form) == ["invokeaction"]

    assert {:ok, event} = Wotex.EventAffordance.new(document["events"]["alarm"])
    assert {:ok, [form]} = Wotex.EventAffordance.forms(event)
    assert Wotex.EventAffordance.operations(event, form) == ["subscribeevent", "unsubscribeevent"]
  end

  defp valid_td_map do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:example:sensor:1",
      "title" => "Temperature Sensor",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "properties" => %{
        "temperature" => %{
          "type" => "number",
          "readOnly" => true,
          "forms" => [
            %{
              "href" => "https://example.test/sensors/1/properties/temperature",
              "op" => "readproperty"
            }
          ]
        }
      },
      "x-example:calibration" => %{"offset" => 0.25}
    }
  end
end
