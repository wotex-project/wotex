defmodule Wotex.BLE.UUID do
  @moduledoc """
  Normalizes Bluetooth UUIDs and their Attribute Protocol representation.

  `normalize/1` accepts 16-bit and 32-bit integer or hexadecimal forms and the
  canonical 128-bit text form. It returns lowercase canonical text without
  consulting a Bluetooth registry. `encode/1` always expands short identities to a 16-octet little-endian
  Attribute Protocol representation, and `decode/1` accepts
  exact 16-bit or 128-bit encodings.

  The functions are pure and return `Wotex.BLE.Error` for malformed, oversized,
  or unsupported representations. Normalization establishes identifier syntax
  only; it does not assert that a UUID is assigned, that a service exists, or
  that a characteristic belongs to a selected peer.

  ## Examples

      iex> {:ok, uuid} = Wotex.BLE.UUID.normalize(0x2A19)
      iex> {:ok, bytes} = Wotex.BLE.UUID.encode(uuid)
      iex> byte_size(bytes)
      16
      iex> Wotex.BLE.UUID.decode(bytes)
      {:ok, "00002a19-0000-1000-8000-00805f9b34fb"}
  """
  alias Wotex.BLE.Error
  @suffix "00001000800000805f9b34fb"

  @doc "Returns a lowercase canonical UUID from 16/32-bit integers or UUID text."
  @spec normalize(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def normalize(value) when is_integer(value) and value in 0..4_294_967_295,
    do: canonical(String.pad_leading(Integer.to_string(value, 16), 8, "0") <> @suffix)

  def normalize("0x" <> text) when byte_size(text) in [4, 8], do: normalize(text)

  def normalize(text) when is_binary(text) and byte_size(text) <= 36 do
    compact = String.replace(text, "-", "")

    decoded = if valid_text?(text), do: Base.decode16(compact, case: :mixed), else: :error

    case {byte_size(compact), decoded} do
      {size, {:ok, _}} when size in [4, 8] ->
        canonical(String.pad_leading(compact, 8, "0") <> @suffix)

      {32, {:ok, _}} ->
        canonical(compact)

      _ ->
        {:error, Error.new(:invalid_uuid)}
    end
  end

  def normalize(_), do: {:error, Error.new(:invalid_uuid)}

  @doc "Encodes a UUID as a 16-octet ATT UUID, including expansion of short identities."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, text} <- normalize(value) do
      {:ok, bytes} = Base.decode16(String.replace(text, "-", ""), case: :mixed)
      {:ok, :binary.list_to_bin(Enum.reverse(:binary.bin_to_list(bytes)))}
    end
  end

  @doc "Decodes ATT UUIDs of exactly 2 or 16 octets."
  @spec decode(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def decode(<<value::16-little>>), do: normalize(value)
  def decode(<<value::128-little>>), do: canonical(Base.encode16(<<value::128>>, case: :lower))
  def decode(_), do: {:error, Error.new(:invalid_uuid)}

  defp valid_text?(text) do
    byte_size(text) in [4, 8, 32] or
      Regex.match?(~r/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/, text)
  end

  defp canonical(hex) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary>> =
      String.downcase(hex)

    {:ok, "#{a}-#{b}-#{c}-#{d}-#{e}"}
  end
end
