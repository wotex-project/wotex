defmodule Wotex.BACnet.IPv4Packet do
  @moduledoc """
  Encodes and validates bounded BACnet/IP datagrams with the pinned packet codecs.

  The four-byte BVLL header must identify IPv4 and declare exactly the received
  size. The package permits at most 1536 bytes before decoding. BACstack owns
  BVLC, NPCI and network-message decoding; this boundary keeps their failures
  payload-free and rejects zero-hop routed frames. APDU bytes remain unchanged
  for the client's service decoder and its stricter 1476-byte admission limit.

  Decoding does not acknowledge a confirmed service or authorize forwarding to
  a consumer. The owned transport reserves a receipt before handing a decoded
  frame to the stack, and the client independently validates service identity.

  Encoding uses BACstack's public NPCI and APDU builder and constructs the IPv4
  BVLL envelope locally. It preserves explicit BVLC and header options, limits
  APDU data to 1476 bytes and complete datagrams to 1536 bytes, and converts
  codec exceptions into payload-free errors. Socket and destination policy
  belong to `Wotex.BACnet.IngressTransport`.
  """

  alias BACnet.Protocol
  alias BACnet.Protocol.NPCI
  alias BACnet.Stack.TransportBehaviour

  @doc "Builds one bounded datagram without opening a socket or resolving an interface."
  @spec encode(iodata() | struct(), boolean(), keyword()) ::
          {:ok, binary()} | {:error, atom()}
  def encode(data, broadcast, opts \\ [])

  def encode(data, broadcast, opts) when is_boolean(broadcast) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         broadcast = broadcast or Keyword.get(opts, :is_broadcast, false),
         {:ok, {npci, apdu}} <- TransportBehaviour.build_bacnet_packet(data, broadcast, opts),
         :ok <- admit_apdu(apdu, opts) do
      envelope(npci, apdu, broadcast, opts)
    else
      {:error, reason}
      when reason in [:apdu_too_long, :data_empty, :invalid_expects_reply_for_broadcast] ->
        {:error, reason}

      _ ->
        {:error, :malformed}
    end
  rescue
    _ -> {:error, :malformed}
  catch
    _, _ -> {:error, :malformed}
  end

  def encode(_, _, _), do: {:error, :malformed}

  defp admit_apdu(apdu, opts) do
    case IO.iodata_length(apdu) do
      size when size > 1476 -> {:error, :apdu_too_long}
      0 -> if is_nil(opts[:bvlc]), do: {:error, :data_empty}, else: :ok
      _ -> :ok
    end
  end

  defp envelope(npci, apdu, broadcast, opts) do
    if opts[:skip_headers] == true do
      {:ok, IO.iodata_to_binary(apdu)}
    else
      bvlc = Keyword.get(opts, :bvlc) || if(broadcast, do: <<11>>, else: <<10>>)
      <<function, extension::binary>> = bvlc
      size = 4 + byte_size(extension) + IO.iodata_length(npci) + IO.iodata_length(apdu)

      if size <= 1536,
        do: {:ok, IO.iodata_to_binary([<<0x81, function, size::16>>, extension, npci, apdu])},
        else: {:error, :oversize}
    end
  end

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
