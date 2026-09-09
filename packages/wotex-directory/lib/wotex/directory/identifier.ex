defmodule Wotex.Directory.Identifier do
  @moduledoc """
  Consumer identifier-generation port for anonymous Thing Descriptions.

  Generated values must be absolute Internationalized Resource Identifier (IRI)
  strings. The package validates the result before repository access.

  The port is consulted only when a submitted Thing Description has no `id`.
  A generator may use a sequence, a random identifier, or an external naming
  service, but it must return the identifier through the tagged callback
  result. Repository collision handling remains part of directory
  registration rather than this behavior.

  `valid?/1` accepts a non-empty, valid UTF-8 string with an RFC 3986-style
  scheme and rejects spaces and control characters. It checks the structural
  requirements imposed by this library; it does not establish ownership,
  dereferenceability, or uniqueness.
  """

  @callback generate(state :: term()) :: {:ok, String.t()} | {:error, term()}

  @spec valid?(term()) :: boolean()
  @doc "Reports whether a term is a non-empty absolute IRI string."
  def valid?(identifier) when is_binary(identifier) do
    String.valid?(identifier) and identifier != "" and no_space_or_control?(identifier) and
      absolute?(identifier)
  end

  def valid?(_), do: false

  defp no_space_or_control?(identifier) do
    not Regex.match?(~r/[\x00-\x20]/u, identifier)
  end

  defp absolute?(identifier) do
    case URI.parse(identifier) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.-]*\z/, scheme)

      _ ->
        false
    end
  end
end
