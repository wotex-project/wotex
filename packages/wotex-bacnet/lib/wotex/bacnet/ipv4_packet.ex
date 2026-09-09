defmodule Wotex.BACnet.IPv4Packet do
  @moduledoc """
  Validates a bounded BACnet/IP datagram before invoking the pinned packet codecs.

  The four-byte BVLL header must identify IPv4 and declare exactly the received
  size. The package permits at most 1536 bytes before decoding. BACstack owns
  BVLC, NPCI and network-message decoding; this boundary keeps their failures
  payload-free and rejects zero-hop routed frames. APDU bytes remain unchanged
  for the client's service decoder and its stricter 1476-byte admission limit.

  Decoding does not acknowledge a confirmed service or authorize forwarding to
  a consumer. The owned transport reserves a receipt before handing a decoded
  frame to the stack, and the client independently validates service identity.
  """

  alias BACnet.Protocol
  alias BACnet.Protocol.NPCI

  @doc "Decodes one complete datagram, retaining its exact APDU bytes when present."
  @spec decode(binary()) :: {:ok, tuple()} | {:error, :oversize | :malformed}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) > 1536, do: {:error, :oversize}

  def decode(<<0x81, function, length::16, rest::binary>> = bytes)
      when byte_size(bytes) == length do
    case Protocol.decode_bvll(0x81, function, rest) do
      {:ok, {_, bvlc, npci_data}} -> decode_npci(bvlc, npci_data)
      _ -> {:error, :malformed}
    end
  rescue
    _ -> {:error, :malformed}
  end

  def decode(_), do: {:error, :malformed}

  defp decode_npci(bvlc, <<>>), do: {:ok, {:bvlc, bvlc}}

  defp decode_npci(bvlc, bytes) do
    with {:ok, {%NPCI{hopcount: hopcount} = npci, payload}} <- Protocol.decode_npci(bytes),
         true <- is_nil(hopcount) or hopcount > 0,
         {:ok, {kind, data}} <- Protocol.decode_npdu(npci, payload) do
      {:ok, {kind, bvlc, npci, data}}
    else
      _ -> {:error, :malformed}
    end
  end
end
