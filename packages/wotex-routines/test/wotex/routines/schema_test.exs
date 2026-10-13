defmodule Wotex.Routines.SchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup_all do
    priv =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    schema =
      priv
      |> Path.join("schemas/wro-01.schema.json")
      |> File.read!()
      |> JSON.decode!()

    corpus =
      priv
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    %{schema: ExJsonSchema.Schema.resolve(schema), corpus: corpus}
  end

  test "the offline schema accepts the independently authored contract corpus", context do
    values =
      context.corpus["bases"] ++
        [context.corpus["fact"], context.corpus["limits"], context.corpus["registry"]]

    for value <- values do
      assert :ok == ExJsonSchema.Validator.validate(context.schema, value)
    end
  end

  test "each mandatory basis member is required and unknown semantics are refused", context do
    basis = hd(context.corpus["bases"])

    for key <- Map.keys(basis) do
      assert {:error, _} = ExJsonSchema.Validator.validate(context.schema, Map.delete(basis, key))
    end

    for data <- [
          Map.put(basis, "script", "run"),
          put_in(basis, ["affordance", "operation"], "toggle"),
          put_in(basis, ["value", "unit", "dimension"], "battery_fraction_from_voltage"),
          put_in(basis, ["analysis", "profile"], %{"id" => "undeclared"}),
          put_in(basis, ["timing", "uncertainty"], "assume_success")
        ] do
      assert {:error, _} = ExJsonSchema.Validator.validate(context.schema, data)
    end
  end
end
