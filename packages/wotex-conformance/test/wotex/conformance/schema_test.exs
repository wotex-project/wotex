defmodule Wotex.Conformance.SchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "all portable schemas are valid JSON Schema 2020-12 documents" do
    schema_directory = Path.expand("../../../priv/schemas", __DIR__)
    schemas = Path.wildcard(Path.join(schema_directory, "*.schema.json"))

    assert length(schemas) == 10

    for path <- schemas do
      assert {:ok, schema} = path |> File.read!() |> Jason.decode()
      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert String.starts_with?(schema["$id"], "https://wotex.io/schemas/conformance/")
      assert is_binary(schema["title"])
    end
  end
end
