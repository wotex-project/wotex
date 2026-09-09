defmodule Wotex.Directory.Introduction do
  @moduledoc """
  Value for the W3C WoT Discovery well-known Introduction mechanism.

  A transport host serves the directory's own Thing Description at `path`.
  This value never contains or reads directory entries.

  `new/1` validates the supplied `Wotex.ThingDescription` and returns the
  fixed well-known path `/.well-known/wot` together with the
  `application/td+json` media type. The resulting value describes how a
  client discovers the directory service itself; listing or retrieving
  registered Things is a separate directory operation.

  This module contains no HTTP server and performs no content negotiation.
  A transport adapter is responsible for exposing the value, choosing status
  codes and headers, and serializing the validated Thing Description.
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

      {:error, _} ->
        invalid()
    end
  end

  def new(_), do: invalid()

  defp invalid, do: {:error, Error.new(:invalid_service, :configuration, :introduction)}
end
