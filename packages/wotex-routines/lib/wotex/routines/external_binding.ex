defmodule Wotex.Routines.ExternalBinding do
  @moduledoc false

  alias Wotex.Routines.{Error, Input, Limits, Validation}

  @fields ~w(format profile_digest source_id source_epoch source_time_basis input_mapping)

  @doc false
  @spec validate(map(), String.t(), map(), Limits.t(), :stale_binding_basis | :stale_edge) ::
          :ok | {:error, Error.t()}
  def validate(data, name, program, limits, stale) do
    context = program["context"]
    binding = context["bindings"][name]
    selected = Enum.find(context["bases"], &(&1["id"] == binding["basis"]["id"]))

    with :ok <- Validation.fields(data, @fields),
         {:ok, expected} <- Input.binding_basis(data["input_mapping"], context["registry"], limits),
         mapping = expected["input_mapping"],
         true <-
           data == expected and mapping["legacy_basis_ref"] == binding["basis"] and
             mapping["basis"] == selected do
      :ok
    else
      false -> Error.refusal(stale)
      error -> error
    end
  end
end
