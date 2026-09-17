defmodule Wotex.CoAP.Test.OSCORE do
  @moduledoc false

  # RFC 8613 (July 2019) primitives for test-owned protected peers: HKDF context
  # derivation (3.2), AES-CCM-16-64-128 with default HKDF SHA-256, nonce (5.2),
  # external AAD (5.4), plaintext (5.3) and the OSCORE option (6.1). Only the
  # default algorithms and an absent ID Context are supported.

  import Bitwise
  alias Wotex.CoAP.{Codec, Message}

  @algorithm 10
  @key_length 16
  @nonce_length 13
  @tag_length 8
  @outer_options [3, 6, 7, 9, 35, 39]

  defstruct [:sender_id, :recipient_id, :sender_key, :recipient_key, :common_iv]

  @type t :: %__MODULE__{
          sender_id: binary(),
          recipient_id: binary(),
          sender_key: binary(),
          recipient_key: binary(),
          common_iv: binary()
        }

  @spec context(binary(), binary(), binary(), binary()) :: t()
  def context(secret, salt, sender_id, recipient_id) do
    %__MODULE__{
      sender_id: sender_id,
      recipient_id: recipient_id,
      sender_key: derive(secret, salt, sender_id, "Key", @key_length),
      recipient_key: derive(secret, salt, recipient_id, "Key", @key_length),
      common_iv: derive(secret, salt, <<>>, "IV", @nonce_length)
    }
  end

  @spec info(binary(), binary(), non_neg_integer()) :: binary()
  def info(id, type, length),
    do: cbor([{:bytes, id}, nil, @algorithm, {:text, type}, length])

  @spec nonce(t(), binary(), binary()) :: binary()
  def nonce(%__MODULE__{common_iv: iv}, id_piv, piv) do
    padded = <<byte_size(id_piv)>> <> pad(id_piv, @nonce_length - 6) <> pad(piv, 5)
    :crypto.exor(padded, iv)
  end

  @spec aad(binary(), binary()) :: binary()
  def aad(request_kid, request_piv) do
    array = cbor([1, [@algorithm], {:bytes, request_kid}, {:bytes, request_piv}, {:bytes, <<>>}])
    cbor([{:text, "Encrypt0"}, {:bytes, <<>>}, {:bytes, array}])
  end

  @spec piv(non_neg_integer()) :: binary()
  def piv(0), do: <<0>>
  def piv(sequence), do: :binary.encode_unsigned(sequence)

  @spec option(binary() | nil, binary() | nil) :: binary()
  def option(nil, nil), do: <<>>

  def option(piv, kid) do
    piv = piv || <<>>
    flags = byte_size(piv) ||| if(kid, do: 0x08, else: 0)
    <<flags>> <> piv <> (kid || <<>>)
  end

  @spec parse_option(binary()) :: {:ok, %{piv: binary() | nil, kid: binary() | nil}} | :error
  def parse_option(<<>>), do: {:ok, %{piv: nil, kid: nil}}

  def parse_option(<<0::3, 0::1, kid_flag::1, length::3, rest::binary>>)
      when length <= 5 and byte_size(rest) >= length do
    <<piv::binary-size(^length), kid::binary>> = rest
    piv = if length == 0, do: nil, else: piv

    case {kid_flag, kid} do
      {1, kid} -> {:ok, %{piv: piv, kid: kid}}
      {0, <<>>} -> {:ok, %{piv: piv, kid: nil}}
      _ -> :error
    end
  end

  def parse_option(_), do: :error

  @spec seal(binary(), binary(), binary(), binary()) :: binary()
  def seal(key, nonce, aad, plaintext) do
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_ccm, key, nonce, plaintext, aad, @tag_length, true)

    ciphertext <> tag
  end

  @spec open(binary(), binary(), binary(), binary()) :: {:ok, binary()} | :error
  def open(key, nonce, aad, sealed) when byte_size(sealed) > @tag_length do
    size = byte_size(sealed) - @tag_length
    <<ciphertext::binary-size(^size), tag::binary>> = sealed

    case :crypto.crypto_one_time_aead(:aes_128_ccm, key, nonce, ciphertext, aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  def open(_, _, _, _), do: :error

  @doc false
  @spec plaintext(0..255, [{non_neg_integer(), binary()}], binary()) :: binary()
  def plaintext(code, options, payload) do
    message = %Message{type: :con, code: code, message_id: 0, options: options, payload: payload}
    {:ok, <<_::8, ^code, _::16, rest::binary>>} = Codec.encode(message)
    <<code>> <> rest
  end

  @spec parse_plaintext(binary()) :: {:ok, Message.t()} | :error
  def parse_plaintext(<<code, rest::binary>>) do
    case Codec.decode(<<1::2, 0::2, 0::4, code, 0::16>> <> rest) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> :error
    end
  end

  def parse_plaintext(_), do: :error

  @spec inner?(non_neg_integer()) :: boolean()
  def inner?(number), do: number not in @outer_options

  defp derive(secret, salt, id, type, length) do
    salt = if salt == <<>>, do: <<0::256>>, else: salt
    prk = :crypto.mac(:hmac, :sha256, salt, secret)
    binary_part(:crypto.mac(:hmac, :sha256, prk, info(id, type, length) <> <<1>>), 0, length)
  end

  defp pad(value, size), do: <<0::size((size - byte_size(value)) * 8)>> <> value

  defp cbor(nil), do: <<0xF6>>
  defp cbor({:bytes, value}), do: head(2, byte_size(value)) <> value
  defp cbor({:text, value}), do: head(3, byte_size(value)) <> value
  defp cbor(value) when is_integer(value) and value >= 0, do: head(0, value)

  defp cbor(values) when is_list(values),
    do: head(4, length(values)) <> Enum.map_join(values, &cbor/1)

  defp head(major, value) when value < 24, do: <<major::3, value::5>>
  defp head(major, value) when value < 256, do: <<major::3, 24::5, value>>
  defp head(major, value) when value < 65_536, do: <<major::3, 25::5, value::16>>
end
