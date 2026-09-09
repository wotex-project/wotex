defmodule Wotex.CoAP.Datagram.DTLS do
  @moduledoc """
  Owns one explicitly authenticated DTLS 1.2 association through OTP SSL.

  The PSK adapter enables only TLS_PSK_WITH_AES_128_GCM_SHA256 after checking
  runtime support. The configured client identity and key remain fixed; a server
  hint cannot select another credential. PKI permits only
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 with supplied trust roots, an exact SAN
  identity and immutable supplied CRLs. OTP owns record authentication, replay
  protection, certificate paths and handshake retransmission. CoAP exchanges
  retain their own owner.
  """

  # SSL is loaded only by explicit open/3; the SSL PLT checks every call statically.
  @compile {:no_warn_undefined, :ssl}
  @behaviour Wotex.CoAP.Datagram
  use GenServer
  import Kernel, except: [send: 2]
  alias Wotex.CoAP.{Datagram, Error, Lifetime, Security}
  alias Wotex.CoAP.Security.{CRLCache, Peer, PKI}
  @psk_cipher %{key_exchange: :psk, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}
  @pki_cipher %{key_exchange: :ecdhe_rsa, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}

  @impl Datagram
  @spec open(Datagram.config(), pid(), pos_integer()) ::
          {:ok, Datagram.handle()} | {:error, Error.t()}
  def open(
        %{host: host, port: port, generation: generation, options: [security: security]} = config,
        owner,
        timeout
      )
      when map_size(config) == 4 and is_tuple(host) and port in 1..65_535 and
             is_reference(generation) and is_pid(owner) and node(owner) == node() and
             timeout in 1..60_000 do
    with :ok <- Security.validate(security),
         true <- valid_ip?(host),
         :ok <- prepare_ssl(security),
         {:ok, pid} <- GenServer.start(__MODULE__, {config, owner, timeout}, timeout: timeout + 100) do
      {:ok, %{pid: pid, generation: generation}}
    else
      {:error, %Error{}} = error -> error
      {:error, _} -> failure(:security_handshake_failed)
      _ -> failure(:invalid_datagram_config)
    end
  end

  def open(_, _, _), do: failure(:invalid_datagram_config)

  @impl Datagram
  @spec send(Datagram.handle(), binary()) :: :ok | {:error, Error.t()}
  def send(handle, bytes) when is_binary(bytes) and byte_size(bytes) <= 1152,
    do: call(handle, {:send, bytes})

  def send(_, _), do: failure(:invalid_datagram)

  @impl Datagram
  @spec set_active_once(Datagram.handle()) :: :ok | {:error, Error.t()}
  def set_active_once(handle), do: call(handle, :arm)

  @impl Datagram
  @spec close(Datagram.handle()) :: :ok | {:error, Error.t()}
  def close(handle) do
    case identity(handle) do
      :owned -> stop(handle)
      :closed -> :ok
      :invalid -> failure(:invalid_datagram_handle)
    end
  end

  @impl GenServer
  def init({config, owner, timeout}) do
    Process.put(:wotex_coap_dtls, {__MODULE__, config.generation})
    lifetime = Lifetime.start([owner], 0)
    monitor = Process.monitor(owner)
    security = Keyword.fetch!(config.options, :security)

    case :ssl.connect(config.host, config.port, ssl_options(security, config.host), timeout) do
      {:ok, socket} -> authenticated(socket, config, owner, monitor, lifetime)
      _ -> {:stop, Error.new(:security_handshake_failed)}
    end
  end

  @impl GenServer
  def handle_call({generation, operation}, _, %{config: %{generation: generation}} = state) do
    result =
      case operation do
        {:send, bytes} -> :ssl.send(state.socket, bytes)
        :arm -> :ssl.setopts(state.socket, active: :once)
        _ -> {:error, :invalid_operation}
      end

    {:reply, normalize(result), state}
  end

  def handle_call(_, _, state), do: {:reply, failure(:invalid_datagram_handle), state}

  @impl GenServer
  def handle_info({:ssl, socket, bytes}, %{socket: socket} = state) do
    deliver(state, {:data, state.config.host, state.config.port, bytes})
    {:noreply, state}
  end

  def handle_info({:ssl_closed, socket}, %{socket: socket} = state),
    do: {:stop, :normal, state}

  def handle_info({:ssl_error, socket, _}, %{socket: socket} = state) do
    deliver(state, {:error, :transport_error})
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    :ssl.close(state.socket, 50)
    deliver(state, :closed)
  end

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:log, _} -> {:log, []}
      {key, _} -> {key, :redacted}
    end)
  end

  defp authenticated(socket, config, owner, monitor, lifetime) do
    cipher = cipher(Keyword.fetch!(config.options, :security))

    with {:ok, information} <-
           :ssl.connection_information(socket, [:protocol, :selected_cipher_suite]),
         true <- Keyword.get(information, :protocol) == :"dtlsv1.2",
         true <- Keyword.get(information, :selected_cipher_suite) == cipher,
         {:ok, {host, port}} <- :ssl.peername(socket),
         true <- host == config.host and port == config.port do
      {:ok,
       %{
         socket: socket,
         config: Map.drop(config, [:options]),
         owner: owner,
         monitor: monitor,
         lifetime: lifetime
       }}
    else
      _ ->
        :ssl.close(socket, 50)
        {:stop, Error.new(:security_handshake_failed)}
    end
  end

  defp prepare_ssl(security) do
    cipher = cipher(security)
    category = if security.mode == :dtls_psk, do: :anonymous, else: :all

    with {:ok, _} <- Application.ensure_all_started(:ssl),
         true <- cipher in :ssl.cipher_suites(category, :"dtlsv1.2"),
         [^cipher] <- :ssl.filter_cipher_suites([cipher], []),
         do: :ok,
         else: (_ -> failure(:unsupported_security))
  catch
    _, _ -> failure(:unsupported_security)
  end

  defp cipher(%Security{mode: :dtls_psk}), do: @psk_cipher
  defp cipher(%Security{mode: :dtls_pki}), do: @pki_cipher

  defp ssl_options(security, host) do
    [
      if(tuple_size(host) == 8, do: :inet6, else: :inet),
      protocol: :dtls,
      versions: [:"dtlsv1.2"],
      ciphers: [cipher(security)],
      active: false,
      mode: :binary,
      log_level: :none,
      reuse_sessions: false,
      max_handshake_size: 1_048_576
    ] ++ credential_options(security)
  end

  defp credential_options(%Security{mode: :dtls_psk} = security) do
    [
      verify: :verify_none,
      psk_identity: :binary.bin_to_list(security.identity),
      user_lookup_fun: {&lookup/3, security}
    ]
  end

  defp credential_options(%Security{mode: :dtls_pki} = security) do
    {:ok, type, _} = PKI.private_key(security.private_key)

    server_name =
      case security.server_identity do
        {:dns, name} -> String.to_charlist(name)
        {:ip, _} -> :disable
      end

    [
      verify: :verify_peer,
      cacerts: security.trust_roots,
      cert: security.certificate,
      key: {type, security.private_key},
      depth: 8,
      crl_check: true,
      crl_cache: {CRLCache, {:supplied, security.crls}},
      verify_fun: {&Peer.verify/3, security.server_identity},
      server_name_indication: server_name
    ]
  end

  defp lookup(:psk, hint, %Security{key: key}) when is_binary(hint) or hint == :undefined,
    do: {:ok, key}

  defp lookup(_, _, _), do: :error

  defp call(handle, operation) do
    case identity(handle) do
      :owned -> GenServer.call(handle.pid, {handle.generation, operation}, 1000)
      :closed -> failure(:connection_closed)
      :invalid -> failure(:invalid_datagram_handle)
    end
  catch
    :exit, _ -> failure(:connection_closed)
  end

  defp stop(handle) do
    GenServer.stop(handle.pid, :normal, 100)
  catch
    :exit, {reason, _} when reason in [:noproc, :normal] ->
      :ok

    :exit, _ ->
      if identity(handle) == :owned do
        monitor = Process.monitor(handle.pid)
        Process.exit(handle.pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> :ok
        after
          100 -> Process.demonitor(monitor, [:flush])
        end
      end

      failure(:cleanup_timeout)
  end

  defp identity(%{pid: pid, generation: generation} = handle)
       when map_size(handle) == 2 and is_pid(pid) and node(pid) == node() and pid != self() and
              is_reference(generation) do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_dtls}) do
      :undefined -> :closed
      {{:dictionary, :wotex_coap_dtls}, {__MODULE__, ^generation}} -> :owned
      _ -> :invalid
    end
  end

  defp identity(_), do: :invalid

  defp valid_ip?(host) do
    maximum = if tuple_size(host) == 4, do: 255, else: 65_535

    tuple_size(host) in [4, 8] and
      Enum.all?(Tuple.to_list(host), &(is_integer(&1) and &1 in 0..maximum))
  end

  defp deliver(state, event),
    do: Kernel.send(state.owner, {:wotex_datagram, state.config.generation, event})

  defp normalize(:ok), do: :ok
  defp normalize(_), do: failure(:transport_error)
  defp failure(code), do: {:error, Error.new(code)}
end
