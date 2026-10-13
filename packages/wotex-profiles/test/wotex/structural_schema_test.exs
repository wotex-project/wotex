defmodule Wotex.Profiles.StructuralSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.Test.Fixtures, as: F

  @schemas Path.expand("../../priv/schemas", __DIR__)

  test "offline draft-07 schemas validate both independent fixture families" do
    for kind <- ~w(profile definition unit) do
      schema = schema(kind)

      for family <- ~w(industrial research) do
        value =
          if kind == "unit",
            do: F.json(family <> "-definition")["unit"],
            else: F.json(family <> "-" <> kind)

        assert :ok = ExJsonSchema.Validator.validate(schema, value)

        assert {:error, _} =
                 ExJsonSchema.Validator.validate(schema, Map.put(value, "foreign", true))
      end
    end
  end

  test "registration schema is standalone and rejects profile-authored executable extensions" do
    schema = schema("binding")

    value = %{
      "id" => "urn:example:binding:register",
      "version" => "1.0.0",
      "sha256" => String.duplicate("a", 64),
      "selector_schema" => %{
        "type" => "object",
        "properties" => %{"register" => %{"type" => "integer"}},
        "additionalProperties" => false
      },
      "operations" => ["readproperty"],
      "capture_fields" => ["model"],
      "raw_value_contract" => F.profile()["binding"],
      "raw_value_schema" => %{"type" => "integer"},
      "codec_contracts" => []
    }

    assert :ok = ExJsonSchema.Validator.validate(schema, value)

    assert {:error, _} =
             ExJsonSchema.Validator.validate(schema, Map.put(value, "module", "Arbitrary.Code"))
  end

  defp schema(name) do
    @schemas
    |> Path.join(name <> ".json")
    |> File.read!()
    |> Jason.decode!()
    |> ExJsonSchema.Schema.resolve()
  end

  test "frozen capture and report documents are offline structural contracts" do
    for name <- ~w(capture checked projection report proposal) do
      assert %ExJsonSchema.Schema.Root{} = schema(name)
    end

    assert :ok = ExJsonSchema.Validator.validate(schema("binding"), F.json("installed-binding"))
    assert :ok = ExJsonSchema.Validator.validate(schema("capture"), F.json("capture"))

    report = %{
      "channel_id" => "sample",
      "profile_sha256" => String.duplicate("a", 64),
      "binding" => F.json("capture")["binding"],
      "capture_epoch" => String.duplicate("c", 32),
      "source_ref" => "synthetic-source",
      "source_epoch" => String.duplicate("e", 32),
      "sequence" => nil,
      "source_time" => nil,
      "receipt_time" => %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "0"},
      "continuity" => "retained",
      "quality" => "unknown",
      "quality_reason" => "missing",
      "value" => %{"type" => "null"}
    }

    assert :ok = ExJsonSchema.Validator.validate(schema("report"), report)

    assert {:error, _} =
             ExJsonSchema.Validator.validate(schema("report"), Map.put(report, "foreign", true))

    assert {:error, _} =
             ExJsonSchema.Validator.validate(
               schema("report"),
               Map.put(report, "sequence", String.duplicate("1", 21))
             )
  end
end
