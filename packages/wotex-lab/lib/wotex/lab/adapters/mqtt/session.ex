if Code.ensure_loaded?(:emqtt) do
  defmodule Wotex.Lab.Adapters.MQTT.Session do
    @moduledoc """
    Every EMQTT broker connection the Lab MQTT adapter owns.

    `subscribe/4` starts a process linked to the runtime subscription owner
    that owns exactly one emqtt connection for that subscription. It connects,
    subscribes to the command's Topic Filters with the command QoS, and sends
    each received Application Message to the owner as
    `{:wotex_transport_frame, %Wotex.Binding.MQTT.Delivery{}}`. A delivery
    larger than the command's payload bound is dropped instead of forwarded.
    When the connection is gone the session sends
    `{:wotex_transport_status, :transport_down}` and exits with a `:shutdown`
    reason, which the owner reports as `:transport_down`; `close/1`
    unsubscribes, disconnects and exits normally.

    `publish/4` and `read/4` serve the calling process. They own a bounded,
    monitored connection instead of a linked session, so a refused broker
    cannot turn into an exit signal in a caller that never asked for a
    session, and they always tear the connection down.

    The credential builds the CONNECT packet only. emqtt runs with
    `reconnect: false`, so no credential can be reused for an automatic
    reconnect; reconnecting is a host decision that re-enters runtime
    credential resolution. No credential reaches the session state, a handle,
    a log line or an error.
    """

    use GenServer

    alias Wotex.Binding.MQTT.{Broker, Command, Delivery}
    alias Wotex.Lab.{Error, Telemetry}

    @messages %{
      broker_host_not_admitted: "the Form broker host is not the configured admitted peer",
      mqtt_client_unavailable: "the EMQTT client process could not be started",
      mqtt_connect_refused: "the broker refused or dropped the connection",
      mqtt_connection_lost: "the broker connection ended before the exchange completed",
      mqtt_publish_rejected: "the broker did not accept the Application Message",
      mqtt_session_unavailable: "the broker session process could not be started",
      mqtt_subscribe_refused: "the broker did not answer the subscription",
      mqtt_subscribe_timeout: "the broker did not confirm the subscription in time",
      mqtt_subscription_denied: "the broker denied a Topic Filter of this subscription",
      mqtt_timeout: "the broker did not answer within the supplied budget",
      no_retained_message: "the broker holds no retained message for the Topic Filter",
      undeliverable_message: "the broker delivered an invalid Application Message"
    }

    @doc "Opens a subscription session linked to the runtime subscription owner."
    @spec subscribe(Command.t(), keyword(), map(), pid()) :: {:ok, pid()} | {:error, Error.t()}
    def subscribe(command, connect_credential, config, owner)
        when is_list(connect_credential) and is_pid(owner) do
      with {:ok, options} <- options(command, connect_credential, config) do
        start_session(command, options, config, owner)
      end
    end

    @doc "Unsubscribes, disconnects and stops a session; a dead session is already closed."
    @spec close(pid()) :: :ok
    def close(session) when is_pid(session) do
      GenServer.stop(session, :normal, 5_000)
    catch
      :exit, _ -> :ok
    end

    @doc "Publishes one Application Message over a bounded connection owned by this call."
    @spec publish(Command.t(), keyword(), map(), pos_integer()) :: :ok | {:error, Error.t()}
    def publish(command, connect_credential, config, budget) do
      with {:ok, options} <- options(command, connect_credential, config) do
        bounded(budget, fn -> exchange(options, &send_message(&1, command)) end)
      end
    end

    @doc "Reads one retained Application Message over a bounded connection owned by this call."
    @spec read(Command.t(), keyword(), map(), pos_integer()) ::
            {:ok, Delivery.t()} | {:error, Error.t()}
    def read(command, connect_credential, config, budget) do
      with {:ok, options} <- options(command, connect_credential, config) do
        bounded(budget, fn -> exchange(options, &retained(&1, command)) end)
      end
    end

    @impl GenServer
    def init(init) do
      Process.flag(:trap_exit, true)

      state = %{
        owner: init.owner,
        parent: init.parent,
        client: nil,
        filters: init.filters,
        limit: init.limit
      }

      {:ok, state, {:continue, {:connect, init.options, init.qos}}}
    end

    @impl GenServer
    def handle_continue({:connect, options, qos}, state) do
      with {:ok, client} <- connect(options),
           :ok <- subscribe_filters(client, state.filters, qos) do
        send(state.parent, {:mqtt_session, self(), :ok})
        {:noreply, %{state | client: client}}
      else
        {:error, error} ->
          send(state.parent, {:mqtt_session, self(), {:error, error}})
          {:stop, :normal, state}
      end
    end

    @impl GenServer
    def handle_info({:publish, message}, state) do
      forward(message, state)
      {:noreply, state}
    end

    def handle_info({:disconnected, _, _}, state), do: down(state)
    def handle_info({:EXIT, client, _}, %{client: client} = state), do: down(state)
    def handle_info({:EXIT, _, _}, state), do: {:stop, :normal, state}
    def handle_info(_, state), do: {:noreply, state}

    @impl GenServer
    def terminate(_, %{client: client, filters: filters}) when is_pid(client) do
      _ = call(fn -> :emqtt.unsubscribe(client, %{}, filters) end)
      stop_client(client)
    end

    def terminate(_, _), do: :ok

    defp start_session(command, options, config, owner) do
      init = %{
        owner: owner,
        parent: self(),
        options: options,
        filters: Command.filters(command),
        qos: Command.qos(command),
        limit: Command.max_payload_bytes(command)
      }

      case GenServer.start_link(__MODULE__, init) do
        {:ok, session} -> await(session, config.connect_timeout * 2)
        {:error, _} -> {:error, failure(:mqtt_session_unavailable, :unavailable)}
      end
    end

    defp await(session, timeout) do
      receive do
        {:mqtt_session, ^session, :ok} -> {:ok, session}
        {:mqtt_session, ^session, {:error, error}} -> {:error, error}
      after
        timeout ->
          Process.unlink(session)
          Process.exit(session, :kill)
          {:error, failure(:mqtt_subscribe_timeout, :timeout)}
      end
    end

    defp down(state) do
      send(state.owner, {:wotex_transport_status, :transport_down})
      {:stop, {:shutdown, :transport_down}, state}
    end

    defp forward(%{payload: payload} = message, state) when is_binary(payload) do
      with true <- byte_size(payload) <= state.limit,
           {:ok, delivery} <- delivery(message) do
        send(state.owner, {:wotex_transport_frame, delivery})
      else
        _ -> dropped()
      end
    end

    defp forward(_, _), do: dropped()

    defp dropped,
      do: Telemetry.event(:mqtt, :subscription, %{dropped: 1}, %{profile: :mqtt})

    defp delivery(%{topic: topic, payload: payload} = message) do
      case Delivery.new(payload,
             topic: topic,
             qos: Map.get(message, :qos, 0),
             retain: Map.get(message, :retain, false) in [true, 1]
           ) do
        {:ok, delivery} -> {:ok, delivery}
        {:error, _} -> :error
      end
    end

    defp bounded(budget, work) do
      caller = self()
      reference = make_ref()

      {worker, monitor} =
        spawn_monitor(fn ->
          Process.flag(:trap_exit, true)
          send(caller, {reference, work.()})
        end)

      collect(reference, worker, monitor, budget)
    end

    defp collect(reference, worker, monitor, budget) do
      receive do
        {^reference, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^worker, _} ->
          {:error, failure(:mqtt_connection_lost, :unavailable)}
      after
        budget ->
          Process.demonitor(monitor, [:flush])
          Process.exit(worker, :kill)
          {:error, failure(:mqtt_timeout, :timeout)}
      end
    end

    defp exchange(options, work) do
      case connect(options) do
        {:ok, client} ->
          result = work.(client)
          stop_client(client)
          result

        {:error, error} ->
          {:error, error}
      end
    end

    defp send_message(client, command) do
      result =
        call(fn ->
          :emqtt.publish(client, Command.topic(command), %{}, Command.payload(command),
            qos: Command.qos(command),
            retain: Command.retain?(command)
          )
        end)

      case result do
        :ok -> :ok
        {:ok, _} -> :ok
        _ -> {:error, failure(:mqtt_publish_rejected, :unavailable)}
      end
    end

    defp retained(client, command) do
      with :ok <- subscribe_filters(client, Command.filters(command), Command.qos(command)),
           :pong <- call(fn -> :emqtt.ping(client) end) do
        first_retained()
      else
        {:error, %Error{} = error} -> {:error, error}
        _ -> {:error, failure(:mqtt_connection_lost, :unavailable)}
      end
    end

    defp first_retained do
      receive do
        {:publish, message} -> retained_delivery(message)
      after
        0 -> {:error, failure(:no_retained_message, :protocol)}
      end
    end

    defp retained_delivery(message) do
      case delivery(message) do
        {:ok, delivery} -> {:ok, delivery}
        :error -> {:error, failure(:undeliverable_message, :protocol)}
      end
    end

    defp connect(options) do
      case call(fn -> :emqtt.start_link(options) end) do
        {:ok, client} -> handshake(client)
        _ -> {:error, failure(:mqtt_client_unavailable, :unavailable)}
      end
    end

    defp handshake(client) do
      case call(fn -> :emqtt.connect(client) end) do
        {:ok, _} ->
          {:ok, client}

        _ ->
          stop_client(client)
          {:error, failure(:mqtt_connect_refused, :unavailable)}
      end
    end

    defp subscribe_filters(client, filters, qos) do
      topics = Enum.map(filters, &{&1, [qos: qos]})

      case call(fn -> :emqtt.subscribe(client, %{}, topics) end) do
        {:ok, _, codes} -> admitted(codes)
        _ -> {:error, failure(:mqtt_subscribe_refused, :unavailable)}
      end
    end

    defp admitted(codes) do
      if Enum.all?(codes, &(is_integer(&1) and &1 < 128)) do
        :ok
      else
        {:error, failure(:mqtt_subscription_denied, :permanent)}
      end
    end

    defp stop_client(client) do
      _ = call(fn -> :emqtt.disconnect(client) end)
      _ = call(fn -> :emqtt.stop(client) end)
      :ok
    end

    defp call(work) do
      work.()
    catch
      _, _ -> :mqtt_call_failed
    end

    defp options(command, connect_credential, config) do
      broker = Command.broker(command)
      host = Broker.host(broker)

      if is_nil(config.host) or config.host == host do
        port = Broker.port(broker) || config.port || default_port(Broker.scheme(broker))
        {:ok, endpoint(broker, host, port, config) ++ connect_credential}
      else
        {:error, failure(:broker_host_not_admitted, :permanent)}
      end
    end

    defp endpoint(broker, host, port, config) do
      base = [
        host: String.to_charlist(host),
        port: port,
        clientid: config.client_id || client_id(config.client_id_prefix),
        proto_ver: :v5,
        clean_start: config.clean_start,
        keepalive: config.keepalive,
        connect_timeout: seconds(config.connect_timeout),
        max_inflight: config.max_inflight,
        properties: %{
          "Session-Expiry-Interval": config.session_expiry_interval,
          "Receive-Maximum": config.receive_maximum,
          "Maximum-Packet-Size": config.maximum_packet_size
        },
        reconnect: false,
        retry_calls_on_reconnect: false
      ]

      base ++ tls_options(Broker.scheme(broker), host, config) ++ will_options(config.will)
    end

    defp default_port(:mqtt), do: 1_883
    defp default_port(:mqtts), do: 8_883

    defp tls_options(:mqtt, _, _), do: []

    defp tls_options(:mqtts, host, config) do
      ssl_options =
        [
          verify: :verify_peer,
          server_name_indication: String.to_charlist(host),
          customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
        ]
        |> trust_store(config.tls_ca_certfile)
        |> put_if(:certfile, config.tls_certfile)
        |> put_if(:keyfile, config.tls_keyfile)

      [ssl: true, ssl_opts: ssl_options]
    end

    defp trust_store(options, nil), do: Keyword.put(options, :cacerts, :public_key.cacerts_get())
    defp trust_store(options, path), do: Keyword.put(options, :cacertfile, String.to_charlist(path))

    defp put_if(options, _, nil), do: options
    defp put_if(options, key, value), do: Keyword.put(options, key, String.to_charlist(value))

    defp will_options(nil), do: []

    defp will_options(will) do
      [
        will_topic: will.topic,
        will_payload: will.payload,
        will_qos: Map.get(will, :qos, 0),
        will_retain: Map.get(will, :retain, false),
        will_props: %{"Will-Delay-Interval": Map.get(will, :delay_interval, 0)}
      ]
    end

    defp client_id(prefix),
      do: prefix <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    defp seconds(milliseconds), do: max(1, div(milliseconds, 1_000))

    defp failure(code, class),
      do: Error.new(code, :transport, Map.fetch!(@messages, code), class: class)
  end
end
