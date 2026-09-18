defmodule Wotex.OPCUA.Bench.NativePeer do
  @moduledoc false

  # The same-stack secure peer of the software lane
  # (`priv/native/paged_peer.c`, built by `wotex.opcua.native.build` as
  # `native-build/wotex_opcua_paged_peer`) on a loopback port, with disposable
  # credentials, and the persistent-Session options of `Wotex.OPCUA.Open62541`
  # for it.
  #
  # The peer serves the SDK between waits of up to 20 ms on its standard input,
  # which would add that wait to every request. A pacing process owns the
  # peer's Port and keeps exactly one statistics request (`s`) in flight: each
  # COUNTERS line the peer prints is answered with the next `s`, so its loop
  # turns continuously and no input is queued. A burst request (`b`, five
  # consecutive writes of the Double Variable `burst` in one server iteration)
  # takes the place of the next `s`.

  alias Wotex.OPCUA.Bench.NativeCredentials

  @enforce_keys [:pacer, :port_number, :namespace, :credentials]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @doc false
  @spec start!(Path.t(), Path.t()) :: t()
  def start!(workspace, directory) do
    executable = Path.join(workspace, "native-build/wotex_opcua_paged_peer")
    unless File.regular?(executable), do: raise("#{executable} is missing; build the workspace")
    credentials = NativeCredentials.write!(directory)
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port_number}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    parent = self()

    pacer =
      spawn_link(fn ->
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            {:line, 4096},
            {:args, [Integer.to_string(port_number), directory]}
          ])

        namespace = await_ready(port, System.monotonic_time(:millisecond) + 10_000)
        send(parent, {self(), :ready, namespace})
        true = Port.command(port, "s")
        pace(port, :queue.new(), [])
      end)

    receive do
      {^pacer, :ready, namespace} ->
        %__MODULE__{
          pacer: pacer,
          port_number: port_number,
          namespace: namespace,
          credentials: credentials
        }
    after
      15_000 -> raise "the same-stack peer did not become ready"
    end
  end

  @doc false
  @spec session_options(t(), Path.t()) :: keyword()
  def session_options(%__MODULE__{} = peer, workspace) do
    executable = Path.join(workspace, "output/bin/wotex_opcua_native")
    guardian = Path.join(workspace, "output/bin/wotex_opcua_custody")

    [
      client: Wotex.OPCUA.Open62541,
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      endpoint: "opc.tcp://127.0.0.1:#{peer.port_number}",
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: "urn:wotex:fixture:client",
      server_uri: "urn:wotex:fixture:server",
      certificate: peer.credentials.client,
      private_key: peer.credentials.client_key,
      server_certificate: peer.credentials.server,
      trust_certificate: peer.credentials.ca,
      crl: peer.credentials.crl,
      authentication: %{type: :anonymous},
      timeout: 5000
    ]
  end

  @doc "Writes five consecutive values to `burst` in one server iteration; returns the last."
  @spec burst(t()) :: float()
  def burst(%__MODULE__{pacer: pacer}), do: call(pacer, :burst)

  @doc "The peer's current Session and SecureChannel counters."
  @spec counters(t()) :: %{sessions: non_neg_integer(), channels: non_neg_integer()}
  def counters(%__MODULE__{pacer: pacer}), do: call(pacer, :counters)

  @doc "Waits up to one second for the peer to report no Session and no SecureChannel."
  @spec await_idle!(t(), non_neg_integer()) :: :ok
  def await_idle!(%__MODULE__{} = peer, attempts \\ 100) do
    case counters(peer) do
      %{sessions: 0, channels: 0} ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(10)
        await_idle!(peer, attempts - 1)

      counters ->
        raise "the peer still holds #{inspect(counters)}"
    end
  end

  @doc "Drops the deliveries of a subscription that reached the caller's mailbox."
  @spec flush(reference()) :: :ok
  def flush(reference) do
    receive do
      {:wotex_opcua, ^reference, _} -> flush(reference)
    after
      0 -> :ok
    end
  end

  @doc "Stops pacing and closes the peer."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pacer: pacer}), do: call(pacer, :stop)

  defp call(pacer, request) do
    reference = make_ref()
    send(pacer, {request, self(), reference})

    receive do
      {^reference, reply} -> reply
    after
      5000 -> raise "the same-stack peer did not answer #{request}"
    end
  end

  # `bursts` queues burst requests in arrival order; `readers` wait for the
  # next COUNTERS line. One command byte is in flight at any time.
  defp pace(port, bursts, readers) do
    receive do
      {^port, {:data, {:eol, "COUNTERS " <> values}}} ->
        [sessions, _, _, _, channels] =
          values
          |> String.split()
          |> Enum.map(&String.to_integer/1)

        for {from, reference} <- readers,
            do: send(from, {reference, %{sessions: sessions, channels: channels}})

        next(port, bursts)
        pace(port, bursts, [])

      {^port, {:data, {:eol, "BURST " <> result}}} ->
        [value, "Good"] = String.split(result)
        {{:value, {from, reference}}, bursts} = :queue.out(bursts)
        send(from, {reference, String.to_float(value)})
        next(port, bursts)
        pace(port, bursts, readers)

      {:burst, from, reference} ->
        pace(port, :queue.in({from, reference}, bursts), readers)

      {:counters, from, reference} ->
        pace(port, bursts, [{from, reference} | readers])

      {:stop, from, reference} ->
        Port.close(port)
        send(from, {reference, :ok})

      {^port, {:exit_status, status}} ->
        raise "the same-stack peer exited with status #{status}"
    end
  end

  defp next(port, bursts),
    do: true = Port.command(port, if(:queue.is_empty(bursts), do: "s", else: "b"))

  defp await_ready(port, deadline) do
    receive do
      {^port, {:data, {:eol, "READY " <> namespace}}} -> String.to_integer(namespace)
      {^port, {:data, _}} -> await_ready(port, deadline)
      {^port, {:exit_status, status}} -> raise "the same-stack peer exited with status #{status}"
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "the same-stack peer did not print READY"
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
