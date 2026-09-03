defmodule WotexContinuum.ThingReference do
  @moduledoc """
  Cross-checks a continuum value's Thing reference against a validated Thing
  Description from the Wotex core.

  The helper delegates Thing Description meaning to the core and performs no
  resolution, authorization, or interaction.
  """

  alias WotexContinuum.Error

  @doc "Validates that a value's `thing_id` equals the Thing Description ID."
  @spec validate(%{thing_id: String.t()}, Wotex.ThingDescription.t()) ::
          :ok | {:error, Error.t()}
  def validate(%{thing_id: thing_id}, %Wotex.ThingDescription{} = thing_description)
      when is_binary(thing_id) do
    with {:ok, validated} <- validate_thing_description(thing_description),
         id when is_binary(id) <- Wotex.ThingDescription.id(validated),
         true <- id == thing_id do
      :ok
    else
      nil ->
        Error.error(:thing_id_required, ["thing_id"], "Thing Description has no ID")

      false ->
        Error.error(
          :thing_id_mismatch,
          ["thing_id"],
          "Thing reference does not match the Thing Description ID"
        )

      {:error, _} = error ->
        error
    end
  end

  def validate(_, %Wotex.ThingDescription{}) do
    Error.error(:thing_id_required, ["thing_id"], "value has no Thing reference")
  end

  def validate(_, _) do
    Error.error(:invalid_type, [], "expected a Wotex Thing Description")
  end

  defp validate_thing_description(thing_description) do
    case Wotex.ThingDescription.validate(thing_description) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        Error.error(:invalid_thing_description, [], "Thing Description validation failed", %{
          errors: Enum.map(List.wrap(errors), &Exception.message/1)
        })
    end
  end
end
