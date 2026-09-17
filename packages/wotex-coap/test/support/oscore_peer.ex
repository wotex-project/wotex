defmodule Wotex.CoAP.Test.OSCOREPeer do
  @moduledoc false

  # A test-owned RFC 8613 server endpoint on one UDP socket. The test process
  # receives each protected request and chooses every response field, so native
  # traces can place exact authenticated responses. It implements no resource
  # model, retransmission or replay window of its own.

  alias Wotex.CoAP.{Codec, Message}
  alias Wotex.CoAP.Test.OSCORE

  @oscore 9
  @observe 6

  defstruct [:socket, :port, :context, sequence: 0]

  @type t :: %__MODULE__{
          socket: :gen_udp.socket(),
          port: :inet.port_number(),
          context: OSCORE.t(),
          sequence: non_neg_integer()
        }

  @type request :: %{
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          outer: Message.t(),
          inner: Message.t(),
          kid: binary(),
          piv: binary()
        }

  @spec open(binary(), binary(), binary()) :: t()
  def open(secret, sender_id, recipient_id) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    context = OSCORE.context(secret, <<>>, sender_id, recipient_id)
    %__MODULE__{socket: socket, port: port, context: context}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}), do: :gen_udp.close(socket)

  @doc "Receives the next datagram and verifies it as a protected request."
  @spec receive_request(t(), timeout()) ::
          {:ok, request()} | {:transport, Message.t()} | {:error, term()}
  def receive_request(%__MODULE__{} = peer, timeout \\ 2_000) do
    with {:ok, {ip, port, bytes}} <- :gen_udp.recv(peer.socket, 0, timeout),
         {:ok, outer} <- Codec.decode(bytes) do
      case Codec.option(outer, @oscore) do
        [value] -> unprotect(peer, ip, port, outer, value)
        [] -> {:transport, outer}
      end
    end
  end

  @doc """
  Sends a protected response to `request`. `partial_iv: :next` includes the next
  sender sequence number; `partial_iv: nil` reuses the request nonce. A response
  with `observe: true` carries the empty Inner Observe option, an Outer Observe
  option and Outer Code 2.05.
  """
  @spec respond(t(), request(), keyword()) :: t()
  def respond(%__MODULE__{} = peer, request, fields) do
    observe = Keyword.get(fields, :observe, false)
    {piv, peer} = partial_iv(peer, Keyword.get(fields, :partial_iv))
    nonce = nonce(peer, request, piv)
    aad = OSCORE.aad(request.kid, request.piv)

    inner_options =
      Keyword.get(fields, :options, []) ++ if(observe, do: [{@observe, <<>>}], else: [])

    plaintext =
      OSCORE.plaintext(
        Keyword.fetch!(fields, :code),
        Enum.sort_by(inner_options, &elem(&1, 0)),
        Keyword.get(fields, :payload, <<>>)
      )

    outer_observe =
      if observe, do: [{@observe, Codec.uint(observe_value(piv))}], else: []

    message = %Message{
      type: Keyword.get(fields, :type, :ack),
      code: if(observe, do: 69, else: 68),
      message_id: Keyword.get(fields, :message_id, request.outer.message_id),
      token: request.outer.token,
      options: Enum.sort_by([{@oscore, OSCORE.option(piv, nil)} | outer_observe], &elem(&1, 0)),
      payload: OSCORE.seal(peer.context.sender_key, nonce, aad, plaintext)
    }

    send_message(peer, request, message)
    peer
  end

  @doc "Sends an empty acknowledgment for a confirmable request."
  @spec acknowledge(t(), request()) :: :ok
  def acknowledge(%__MODULE__{} = peer, request) do
    message = %Message{type: :ack, code: 0, message_id: request.outer.message_id}
    send_message(peer, request, message)
  end

  defp unprotect(peer, ip, port, outer, value) do
    context = peer.context

    with {:ok, %{piv: piv, kid: kid}} when is_binary(piv) and kid == context.recipient_id <-
           OSCORE.parse_option(value),
         {:ok, plaintext} <-
           OSCORE.open(
             context.recipient_key,
             OSCORE.nonce(context, kid, piv),
             OSCORE.aad(kid, piv),
             outer.payload
           ),
         {:ok, inner} <- OSCORE.parse_plaintext(plaintext) do
      {:ok, %{ip: ip, port: port, outer: outer, inner: inner, kid: kid, piv: piv}}
    else
      _ -> {:error, :unverified_request}
    end
  end

  defp partial_iv(peer, nil), do: {nil, peer}

  defp partial_iv(peer, :next),
    do: {OSCORE.piv(peer.sequence), %{peer | sequence: peer.sequence + 1}}

  defp partial_iv(peer, sequence) when is_integer(sequence) and sequence >= peer.sequence,
    do: {OSCORE.piv(sequence), %{peer | sequence: sequence + 1}}

  defp nonce(peer, request, nil), do: OSCORE.nonce(peer.context, request.kid, request.piv)
  defp nonce(peer, _, piv), do: OSCORE.nonce(peer.context, peer.context.sender_id, piv)

  defp observe_value(nil), do: 0
  defp observe_value(piv), do: :binary.decode_unsigned(piv) |> Bitwise.band(0xFFFFFF)

  defp send_message(peer, request, message) do
    {:ok, bytes} = Codec.encode(message)
    :ok = :gen_udp.send(peer.socket, request.ip, request.port, bytes)
  end
end
