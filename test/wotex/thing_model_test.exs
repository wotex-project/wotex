defmodule Wotex.ThingModelTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{Error, ThingModel}

  test "parses a Thing Model 1.1 and preserves source and extensions" do
    json = Jason.encode!(valid_tm_map())

    assert {:ok, tm} = ThingModel.parse(json)
    assert ThingModel.id(tm) == "urn:example:model:thermostat"
    assert ThingModel.to_map(tm)["x-example:profile"] == "building"
    assert {:ok, ^json} = ThingModel.encode(tm, :source)
    assert %ThingModel{} = ThingModel.parse!(json)
    assert Wotex.tm_media_type() == "application/tm+json"
  end

  test "canonical encoding is deterministic and mutation invalidates source bytes" do
    first = valid_tm_map()
    reversed = Enum.reverse(first)
    second = Map.new(reversed)

    assert {:ok, first_tm} = ThingModel.from_map(first)
    assert {:ok, second_tm} = ThingModel.from_map(second)
    assert ThingModel.encode(first_tm, :canonical) == ThingModel.encode(second_tm, :canonical)

    json = Jason.encode!(first)
    assert {:ok, tm} = ThingModel.parse(json)
    assert {:ok, changed} = ThingModel.put_id(tm, "urn:example:model:thermostat:2")
    assert ThingModel.id(changed) == "urn:example:model:thermostat:2"
    assert {:error, %Error{code: :source_unavailable}} = ThingModel.encode(changed, :source)
  end

  test "enforces Thing Model type, TD 1.1 context, JSON values, and limits" do
    assert {:error, errors} =
             valid_tm_map()
             |> Map.put("@type", "ThingModel")
             |> ThingModel.from_map()

    assert Enum.any?(errors, &(&1.code == :schema_violation))

    assert {:error, errors} =
             valid_tm_map()
             |> Map.put("@context", "https://www.w3.org/2019/wot/td/v1")
             |> ThingModel.from_map()

    assert Enum.any?(errors, &(&1.code == :unsupported_context))

    assert {:error, %Error{code: :non_string_key}} =
             valid_tm_map()
             |> Map.put(:private, true)
             |> ThingModel.from_map()

    assert {:error, %Error{code: :byte_limit_exceeded}} =
             valid_tm_map()
             |> Jason.encode!()
             |> ThingModel.parse(max_bytes: 8)

    assert {:error, %Error{code: :node_limit_exceeded}} =
             ThingModel.from_map(valid_tm_map(), max_nodes: 3)

    assert {:ok, _tm} =
             ThingModel.from_map(valid_tm_map(), max_bytes: 0, max_depth: 0, max_nodes: 0)
  end

  test "accepts a TD 1.1 context array and rejects arrays without that context" do
    with_context =
      Map.put(valid_tm_map(), "@context", [
        Wotex.td_context_1_1(),
        %{"x-example" => "https://example.test/vocabulary#"}
      ])

    assert {:ok, _tm} = ThingModel.from_map(with_context)

    without_context =
      Map.put(valid_tm_map(), "@context", ["https://example.test/vocabulary"])

    assert {:error, errors} = ThingModel.from_map(without_context)
    assert Enum.any?(errors, &(&1.code == :unsupported_context))
  end

  test "preserves placeholders, optional pointers, and schema references" do
    map =
      valid_tm_map()
      |> put_in(["properties", "temperature", "maximum"], "{{MAX_TEMPERATURE}}")
      |> put_in(["properties", "temperature", "tm:ref"], "#/schemaDefinitions/temperature")
      |> Map.put("schemaDefinitions", %{
        "temperature" => %{"type" => "number", "unit" => "Cel"}
      })

    assert {:ok, tm} = ThingModel.from_map(map)
    assert ThingModel.to_map(tm) == map
  end

  test "rejects undefined security references at exact paths" do
    map =
      valid_tm_map()
      |> Map.put("security", ["missing"])
      |> Map.put("securityDefinitions", %{"nosec_sc" => %{"scheme" => "nosec"}})

    assert {:error, errors} = ThingModel.from_map(map)

    assert Enum.any?(
             errors,
             &(&1.code == :undefined_security_reference and &1.path == "/security/0" and
                 &1.details == %{reference: "missing"})
           )
  end

  test "checks string, Form, affordance, and combo security references deterministically" do
    map =
      valid_tm_map()
      |> Map.put("security", "defined")
      |> Map.put("securityDefinitions", %{
        "defined" => %{"scheme" => "nosec"},
        "combo/one~raw" => %{
          "scheme" => "combo",
          "allOf" => ["defined", 42, "missing_combo"]
        }
      })
      |> Map.put("forms", [
        %{"href" => "https://example.test", "security" => "missing_form"},
        "ignored"
      ])
      |> Map.put("actions", %{
        "reset/now~raw" => %{
          "forms" => [
            %{"href" => "https://example.test/reset", "security" => [42, "missing_action"]}
          ]
        }
      })
      |> Map.put("events", "ignored")

    assert {:error, errors} = ThingModel.from_map(map)

    assert Enum.any?(errors, &(&1.path == "/forms/0/security"))
    assert Enum.any?(errors, &(&1.path == "/actions/reset~1now~0raw/forms/0/security/1"))

    assert Enum.any?(
             errors,
             &(&1.path == "/securityDefinitions/combo~1one~0raw/allOf/2")
           )
  end

  test "supports staged validation, all encodings, and structured failures" do
    assert {:ok, tm} = ThingModel.from_map(valid_tm_map(), validate: false)
    assert {:ok, ^tm} = ThingModel.validate(tm)
    assert {:ok, compact} = ThingModel.encode(tm, :compact)
    assert {:ok, pretty} = ThingModel.encode(tm, :pretty)
    assert Jason.decode!(compact) == valid_tm_map()
    assert Jason.decode!(pretty) == valid_tm_map()
    assert String.contains?(pretty, "\n")

    assert {:error, %Error{code: :source_unavailable}} = ThingModel.encode(tm, :source)
    assert {:error, %Error{code: :unsupported_encoding}} = ThingModel.encode(tm, :turtle)
    assert {:error, %Error{code: :invalid_json}} = ThingModel.parse(~s({"@type":))
    assert {:error, %Error{code: :invalid_input}} = ThingModel.parse(%{})
    assert {:error, %Error{code: :object_required}} = ThingModel.parse("[]")
    assert_raise Error, fn -> ThingModel.parse!(~s({"@type":)) end

    legacy =
      valid_tm_map()
      |> Map.put("@context", "https://www.w3.org/2019/wot/td/v1")
      |> Jason.encode!()

    assert_raise Error, fn -> ThingModel.parse!(legacy) end

    assert {:error, %Error{code: :invalid_id}} = ThingModel.put_id(tm, "")

    assert {:ok, incomplete} = ThingModel.from_map(%{"title" => "incomplete"}, validate: false)
    assert {:error, errors} = ThingModel.put_id(incomplete, "urn:example:model:incomplete")
    assert errors != []

    unsafe = %ThingModel{document: %{"process" => self()}}
    assert {:error, %Error{code: :encode_failed}} = ThingModel.encode(unsafe, :compact)
  end

  test "reports the pinned W3C schema provenance" do
    assert %{
             standard: "W3C WoT Thing Description 1.1 Thing Model",
             recommendation_date: "2023-12-05",
             upstream_tag: "REC1.1",
             upstream_commit: "7c0b968f403ecdb9594bd882cafbacf544c41fc0",
             upstream_sha256: "d4fecbf6e9713a7c98c85ef8065800b85f72dd690be5016511c72406ed7314f2",
             bundled_sha256: "3c8dedb2a534d089fdbd7fda8eb05a5b13237a2331f42e2af08cdb4a7af9fc7a",
             informative: true
           } = ThingModel.schema_info()
  end

  defp valid_tm_map do
    %{
      "@context" => Wotex.td_context_1_1(),
      "@type" => "tm:ThingModel",
      "id" => "urn:example:model:thermostat",
      "title" => "Thermostat model",
      "properties" => %{
        "temperature" => %{"type" => "number", "unit" => "Cel", "readOnly" => true}
      },
      "tm:optional" => ["/properties/temperature"],
      "x-example:profile" => "building"
    }
  end
end
