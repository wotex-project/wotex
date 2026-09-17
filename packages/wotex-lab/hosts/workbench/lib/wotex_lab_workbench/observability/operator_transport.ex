defmodule WotexLabWorkbench.Observability.OperatorTransport do
  @moduledoc """
  Closed transport profiles for the operator scrape and query listeners.

  The `:local` profile, the default, binds plain HTTP/1 to `127.0.0.1` and
  admits only that peer. The remote profile is a separately admitted
  deployment: `configure_remote/5` requires an explicit IP literal to bind, a
  server certificate and key, a client CA certificate file and a list of 1 to
  16 CIDR ranges. The listener then serves HTTPS with TLS 1.3 only, using the
  strong Plug cipher suite, requires and verifies a client certificate issued
  under that CA (chain depth at most two), issues no session tickets and admits
  a connection only when the socket peer address lies inside an allowed range.
  An IPv4 range does not admit an IPv4-mapped IPv6 peer.

  Forwarding headers never change the peer address, and the listener's Bearer
  credential remains required on top of mutual TLS. Configuration checks that
  the files are regular files but never reads, logs or retains their contents
  beyond the paths. Certificate issuance, rotation and revocation lists are
  operator responsibilities; this module performs no network access.
  """

  alias Wotex.Lab.Error

  @max_path_bytes 4_096
  @max_ranges 16

  @typedoc "An admitted peer range: address and prefix length."
  @type range :: {:inet.ip_address(), non_neg_integer()}

  @typedoc "An admitted operator listener transport."
  @type t ::
          :local
          | %{
              profile: :remote,
              bind: :inet.ip_address(),
              certfile: String.t(),
              keyfile: String.t(),
              client_cacertfile: String.t(),
              allow: [range()]
            }

  @doc "Admits the mutual-TLS remote profile from operator-supplied text values."
  @spec configure_remote(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def configure_remote(bind, certfile, keyfile, client_cacertfile, allow) do
    with {:ok, address} <- address(bind),
         {:ok, ranges} <- ranges(allow) do
      transport = %{
        profile: :remote,
        bind: address,
        certfile: certfile,
        keyfile: keyfile,
        client_cacertfile: client_cacertfile,
        allow: ranges
      }

      with :ok <- validate(transport), do: {:ok, transport}
    end
  end

  @doc "Validates an admitted transport value without opening a socket."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(:local), do: :ok

  def validate(
        %{
          profile: :remote,
          bind: bind,
          certfile: certfile,
          keyfile: keyfile,
          client_cacertfile: client_cacertfile,
          allow: allow
        } = transport
      )
      when map_size(transport) == 6 do
    if ip?(bind) and Enum.all?([certfile, keyfile, client_cacertfile], &file?/1) and
         is_list(allow) and length(allow) in 1..@max_ranges and Enum.all?(allow, &range?/1),
       do: :ok,
       else: invalid()
  end

  def validate(_), do: invalid()

  @doc "The Bandit options that select the transport's scheme, address and TLS policy."
  @spec bandit_options(t(), keyword()) :: keyword()
  def bandit_options(:local, transport_options),
    do: [scheme: :http, ip: {127, 0, 0, 1}, transport_options: transport_options]

  def bandit_options(%{profile: :remote} = transport, transport_options) do
    [
      scheme: :https,
      ip: transport.bind,
      certfile: transport.certfile,
      keyfile: transport.keyfile,
      cipher_suite: :strong,
      transport_options:
        transport_options ++
          [
            cacertfile: transport.client_cacertfile,
            verify: :verify_peer,
            fail_if_no_peer_cert: true,
            depth: 2,
            session_tickets: :disabled
          ]
    ]
  end

  @doc "Whether a socket peer address may use a listener with this transport."
  @spec admitted_peer?(t(), term()) :: boolean()
  def admitted_peer?(:local, peer), do: peer == {127, 0, 0, 1}

  def admitted_peer?(%{profile: :remote, allow: allow}, peer) do
    ip?(peer) and Enum.any?(allow, &inside?(peer, &1))
  end

  def admitted_peer?(_, _), do: false

  defp address(text) when is_binary(text) and byte_size(text) in 1..45 do
    case :inet.parse_strict_address(String.to_charlist(text)) do
      {:ok, address} -> {:ok, address}
      {:error, _} -> invalid()
    end
  end

  defp address(_), do: invalid()

  defp ranges(text) when is_binary(text) and byte_size(text) in 1..1_024 do
    text
    |> String.split(",")
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case range(entry) do
        {:ok, range} -> {:cont, {:ok, [range | acc]}}
        :error -> {:halt, invalid()}
      end
    end)
    |> case do
      {:ok, ranges} when length(ranges) in 1..@max_ranges -> {:ok, Enum.reverse(ranges)}
      _ -> invalid()
    end
  end

  defp ranges(_), do: invalid()

  defp range(entry) do
    with [address, prefix] <- String.split(entry, "/"),
         true <- Regex.match?(~r/\A[0-9]{1,3}\z/, prefix),
         {:ok, address} <- :inet.parse_strict_address(String.to_charlist(address)),
         range = {address, String.to_integer(prefix)},
         true <- range?(range) do
      {:ok, range}
    else
      _ -> :error
    end
  end

  defp range?({address, prefix}) when is_integer(prefix) do
    case address do
      {_, _, _, _} -> ip?(address) and prefix in 0..32
      {_, _, _, _, _, _, _, _} -> ip?(address) and prefix in 0..128
      _ -> false
    end
  end

  defp range?(_), do: false

  defp inside?(peer, {network, prefix})
       when tuple_size(peer) == tuple_size(network) do
    bits = tuple_size(peer) * if(tuple_size(peer) == 4, do: 8, else: 16)
    <<peer_prefix::bitstring-size(^prefix), _::bitstring>> = binary(peer, bits)
    <<network_prefix::bitstring-size(^prefix), _::bitstring>> = binary(network, bits)
    peer_prefix == network_prefix
  end

  defp inside?(_, _), do: false

  defp binary(address, 32), do: address |> Tuple.to_list() |> :binary.list_to_bin()

  defp binary(address, 128),
    do: for(part <- Tuple.to_list(address), into: <<>>, do: <<part::16>>)

  defp ip?({a, b, c, d}), do: Enum.all?([a, b, c, d], &(&1 in 0..255))

  defp ip?({_, _, _, _, _, _, _, _} = address),
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 in 0..65_535))

  defp ip?(_), do: false

  defp file?(path) when is_binary(path) and byte_size(path) in 1..@max_path_bytes,
    do: File.regular?(path)

  defp file?(_), do: false

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_metrics_transport, :metrics, "operator listener transport is invalid")}
end
