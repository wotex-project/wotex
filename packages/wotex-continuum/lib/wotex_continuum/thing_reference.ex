defmodule WotexContinuum.ThingReference do
  @moduledoc """
  Cross-checks a continuum value's Thing reference against a validated Thing
  Description from the Wotex core.

  The helper delegates Thing Description meaning to the core and performs no
  resolution, authorization, or interaction.

  `validate/2` first validates the supplied `Wotex.ThingDescription`, requires
  its identifier, and compares that identifier exactly with the continuum
  value's `thing_id`. A missing reference, invalid Thing Description, or
  mismatch returns a structured `WotexContinuum.Error` at the relevant path.

  Equality confirms only that two explicit references agree. The function does
  not retrieve the Thing Description, establish that it is current, verify an
  external signature, or grant authority over the described Thing. The Wotex
  core continues to own Thing Description parsing and semantics; continuum
  values retain only their project-defined reference.
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
        Error.error(:thing_id_required, :validation, "/thing_id", "Thing Description has no ID")

      false ->
        Error.error(
          :thing_id_mismatch,
          :validation,
          "/thing_id",
          "Thing reference does not match the Thing Description ID"
        )

      {:error, _} = error ->
        error
    end
  end

  def validate(_, %Wotex.ThingDescription{}) do
    Error.error(:thing_id_required, :validation, "/thing_id", "value has no Thing reference")
  end

  def validate(_, _) do
    Error.error(:invalid_type, :validation, "/", "expected a Wotex Thing Description")
  end

  defp validate_thing_description(thing_description) do
    case Wotex.ThingDescription.validate(thing_description) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        Error.error(
          :invalid_thing_description,
          :validation,
          "/",
          "Thing Description validation failed",
          %{
            errors: Enum.map(List.wrap(errors), &Exception.message/1)
          }
        )
    end
  end
end
