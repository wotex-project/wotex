defmodule Wotex.BACnet.CharacterString do
  @moduledoc """
  Preserves a BACnet character-set identifier and its original encoded bytes.

  BACnet CharacterString values carry an encoding selector alongside their
  octets. This struct retains both fields so transport and mapping layers do
  not lose the wire-level character-set identity by converting every value to
  an Elixir string prematurely.

  `new/2` accepts character-set identifiers from 0 through 255 and byte strings
  up to 65,536 bytes. Character set zero denotes UTF-8 in this package and
  therefore requires valid UTF-8 bytes; other identifiers preserve their bytes
  without claiming that the library can
  transcode them. The value contains decoded protocol data and owns no client
  or transport resource.
  """

  alias Wotex.BACnet.Error
  @enforce_keys [:character_set, :bytes]
  defstruct [:character_set, :bytes]
  @type t :: %__MODULE__{character_set: 0..255, bytes: binary()}

  @doc "Retains encoded text identity; character set zero requires valid UTF-8."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(character_set, bytes)
      when is_integer(character_set) and character_set in 0..255 and is_binary(bytes) and
             byte_size(bytes) <= 65_536 do
    if character_set != 0 or String.valid?(bytes),
      do: {:ok, %__MODULE__{character_set: character_set, bytes: bytes}},
      else: {:error, Error.new(:invalid_character_string)}
  end

  def new(_, _), do: {:error, Error.new(:invalid_character_string)}
end
