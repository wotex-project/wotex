defmodule Wotex.SecurityScheme do
  @moduledoc """
  An immutable W3C WoT security-scheme definition.

  The value requires the standard non-empty `scheme` discriminator and
  preserves every additional JSON-compatible member. It describes the security
  mechanism referenced by a Thing Description; it never contains resolved
  credential material and does not perform authentication or authorization.

  Consumers can inspect the discriminator with `scheme/1` or serialize the
  complete declaration with `to_map/1`.
  """

  alias Wotex.Value

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a security scheme with a non-empty `scheme` member."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []) do
    Value.build(
      __MODULE__,
      map,
      [{"scheme", &non_empty_binary?/1, "Security scheme name must be non-empty"}],
      :security_scheme,
      opts
    )
  end

  @doc "Returns the complete preserved security-scheme map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = scheme), do: Value.to_map(scheme)

  @doc "Returns the W3C security-scheme name."
  @spec scheme(t()) :: String.t()
  def scheme(%__MODULE__{value: value}), do: Map.fetch!(value, "scheme")

  defp non_empty_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
end
