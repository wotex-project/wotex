defmodule Wotex.Directory.Identifier do
  @moduledoc """
  Consumer identifier-generation port for anonymous Thing Descriptions.

  Generated values must be absolute IRI strings. The package validates the
  result before repository access.
  """

  @callback generate(state :: term()) :: {:ok, String.t()} | {:error, term()}

  @spec valid?(term()) :: boolean()
  @doc "Reports whether a term is a non-empty absolute IRI string."
  def valid?(identifier) when is_binary(identifier) do
    String.valid?(identifier) and identifier != "" and no_space_or_control?(identifier) and
      absolute?(identifier)
  end

  def valid?(_identifier), do: false

  defp no_space_or_control?(identifier) do
    not Regex.match?(~r/[\x00-\x20]/u, identifier)
  end

  defp absolute?(identifier) do
    case URI.parse(identifier) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.-]*\z/, scheme)

      _uri ->
        false
    end
  end
end
