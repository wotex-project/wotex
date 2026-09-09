defmodule Wotex.BLE.Challenge do
  @moduledoc """
  Represents one bounded, exact-peer pairing prompt with a local deadline.

  `new/1` validates the identifier, peer and prompt value without consulting a
  clock or invoking policy. The connection supplies `deadline_ms` in the BEAM
  monotonic millisecond time domain; it enforces expiry separately. PIN and
  passkey values are excluded from inspection, alongside peer and prompt IDs.
  """

  alias Wotex.BLE.{Error, Peer, UUID}

  @derive {Inspect, only: [:kind, :deadline_ms]}
  @enforce_keys [:id, :peer, :kind, :value, :deadline_ms]
  defstruct @enforce_keys

  @type kind ::
          :confirm_passkey
          | :request_passkey
          | :request_pin
          | :authorize_pairing
          | :authorize_service
          | :display_passkey
          | :display_pin
  @type t :: %__MODULE__{
          id: String.t(),
          peer: Peer.t(),
          kind: kind(),
          value: term(),
          deadline_ms: integer()
        }

  @doc "Validates a pairing prompt; identifiers are 1..64 printable ASCII bytes."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{id: id, peer: peer, kind: kind, value: value, deadline_ms: deadline} = input) do
    with true <- fields?(input),
         true <- text?(id, 64),
         true <- is_integer(deadline) and deadline in -0x8000_0000_0000_0000..0x7FFF_FFFF_FFFF_FFFF,
         {:ok, peer} <- Peer.new(peer),
         {:ok, value} <- value(kind, value) do
      {:ok, %__MODULE__{id: id, peer: peer, kind: kind, value: value, deadline_ms: deadline}}
    else
      _ -> {:error, Error.new(:invalid_challenge)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_challenge)}

  defp fields?(%__MODULE__{} = input), do: map_size(input) == 6
  defp fields?(input), do: map_size(input) == 5

  defp value(kind, nil) when kind in [:request_pin, :request_passkey, :authorize_pairing],
    do: {:ok, nil}

  defp value(:confirm_passkey, value) when is_integer(value) and value in 0..999_999,
    do: {:ok, value}

  defp value(:display_passkey, %{passkey: passkey, entered: entered} = value)
       when map_size(value) == 2 and is_integer(passkey) and passkey in 0..999_999 and
              is_integer(entered) and entered in 0..6,
       do: {:ok, value}

  defp value(:display_pin, value) do
    if text?(value, 16), do: {:ok, value}, else: :error
  end

  defp value(:authorize_service, value), do: UUID.normalize(value)
  defp value(_, _), do: :error

  defp text?(value, max)
       when is_binary(value) and byte_size(value) >= 1 and byte_size(value) <= max,
       do: ascii?(value)

  defp text?(_, _), do: false
  defp ascii?(<<>>), do: true
  defp ascii?(<<byte, rest::binary>>) when byte in 32..126, do: ascii?(rest)
  defp ascii?(_), do: false
end
