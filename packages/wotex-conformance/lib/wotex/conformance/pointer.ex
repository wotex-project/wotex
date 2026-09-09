defmodule Wotex.Conformance.Pointer do
  @moduledoc """
  RFC 6901 JSON Pointer encoding for conformance paths.

  Structured errors, vector projections, and normalized observations address
  one member of a JSON document with a pointer string. `~` is escaped as `~0`
  and `/` as `~1`, so a member name can never be confused with a separator.

  `encode/1` accepts string and integer path segments, preserves their order,
  and returns the empty string for the whole document. `valid?/1` accepts that
  root representation or an absolute pointer containing only the two defined
  escape sequences. The module checks pointer syntax but does not traverse a
  JSON value or verify that the addressed member exists.

  Pointer strings are used as stable public locations rather than Elixir access
  paths. This permits target observations and error reports to retain exact
  field identity without creating atoms from input or exposing an entire source
  document.
  """

  @escape ~r/~(?![01])/

  @doc """
  Encodes pointer segments into one RFC 6901 pointer string.

  Integer segments address array members. An empty segment list encodes the
  whole document as `""`.

      iex> Wotex.Conformance.Pointer.encode(["properties", "a/b", 0])
      "/properties/a~1b/0"
  """
  @spec encode([String.t() | integer()]) :: String.t()
  def encode(segments) when is_list(segments) do
    Enum.map_join(segments, "", &("/" <> escape(&1)))
  end

  @doc """
  Reports whether a value is a syntactically valid JSON Pointer.

  The whole-document pointer `""` is valid; every other pointer starts with
  `/` and contains only `~0` and `~1` escapes.
  """
  @spec valid?(term()) :: boolean()
  def valid?(""), do: true

  def valid?("/" <> _rest = pointer) do
    String.valid?(pointer) and not Regex.match?(@escape, pointer)
  end

  def valid?(_pointer), do: false

  defp escape(segment) when is_integer(segment), do: Integer.to_string(segment)

  defp escape(segment) when is_binary(segment) do
    segment |> String.replace("~", "~0") |> String.replace("/", "~1")
  end
end
