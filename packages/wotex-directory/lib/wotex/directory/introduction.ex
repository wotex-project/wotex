defmodule Wotex.Directory.Introduction do
  @moduledoc """
  Value for the W3C WoT Discovery well-known Introduction mechanism.

  A transport host serves the directory's own Thing Description at `path`.
  This value never contains or reads directory entries.
  """

  alias Wotex.Directory.Error

  @path "/.well-known/wot"
  @media_type "application/td+json"

  @enforce_keys [:path, :media_type, :thing_description]
  defstruct [:path, :media_type, :thing_description]

  @type t :: %__MODULE__{
          path: String.t(),
          media_type: String.t(),
          thing_description: Wotex.ThingDescription.t()
        }

  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Builds the well-known Introduction value from the directory Thing Description."
  def new(%Wotex.ThingDescription{} = thing_description) do
    case Wotex.ThingDescription.validate(thing_description) do
      {:ok, validated} ->
        {:ok,
         %__MODULE__{
           path: @path,
           media_type: @media_type,
           thing_description: validated
         }}

      {:error, _errors} ->
        invalid()
    end
  end

  def new(_thing_description), do: invalid()

  defp invalid, do: {:error, Error.new(:invalid_service, :configuration, :introduction)}
end
