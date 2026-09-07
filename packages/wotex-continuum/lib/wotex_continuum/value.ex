defmodule WotexContinuum.Value do
  @moduledoc """
  Contract shared by every value accepted by `WotexContinuum`.

  Implementations expose a stable wire kind, validate untrusted maps into inert
  structs, and project accepted structs back to string-keyed wire maps. The
  behaviour exists so codecs and registries can handle the complete continuum
  vocabulary without granting any value execution, persistence, or policy
  authority.

  Consumers normally call `WotexContinuum.from_map/1` and
  `WotexContinuum.to_map/1`. Calling a value module directly is useful when the
  expected kind is already known and should not be selected from input.

  `from_map/1` is the documented entry for map-shaped wire input. Value modules
  also expose `new/1` as an alias of `from_map/1`; `new/1` carries keyword
  configuration only in `WotexContinuum.Limits`.
  """

  @doc """
  Returns the exact discriminator used in the value's encoded `kind` field.

  The result is stable wire vocabulary, not an Elixir module name.
  """
  @callback kind() :: String.t()

  @doc """
  Validates an untrusted map and returns an inert continuum value.

  Implementations accept documented atom or string keys, reject unknown or
  malformed contract data, and return a structured `WotexContinuum.Error` for
  expected failures. Construction performs no I/O and invokes no Action. An
  already accepted struct is revalidated instead of trusted.
  """
  @callback from_map(map() | struct()) :: {:ok, struct()} | {:error, WotexContinuum.Error.t()}

  @doc """
  Projects an accepted value into its string-keyed wire representation.

  The returned map is suitable for `WotexContinuum.Codec`; it remains ordinary
  data and does not imply that a consumer admitted it as canonical state.
  """
  @callback to_map(struct()) :: map()
end
