if Code.ensure_loaded?(:emqtt) do
  defmodule Wotex.Lab.Adapters.MQTT.EmqttClient do
    @moduledoc """
    `Wotex.Binding.MQTT.Client` implemented with EMQTT.

    `Wotex.Lab.Adapters.MQTT.Session` owns every connection. `subscribe/4`
    starts one linked to the runtime subscription owner, which receives raw
    deliveries and `:transport_down`; `unsubscribe/4` closes exactly that
    session. `publish/3` and `read/4` run for the calling process over a
    bounded connection that is always torn down: `read/4` subscribes, lets a
    PINGREQ round trip flush the broker's retained delivery for the Topic
    Filter, and distinguishes `:no_retained_message` from `:mqtt_timeout`.

    The credential resolved by the runtime is `nil`, `{:password, user,
    password}`, or a map of security names to those tuples from
    `Wotex.Lab.Adapters.Runtime.StaticRef`. It becomes the CONNECT packet's
    User Name and Password for that one connection and is never stored: emqtt
    runs with `reconnect: false`, so no automatic reconnect can reuse it.

    Configuration is closed, bounded and non-secret. It admits an optional host
    pin, port, random Client Identifier prefix or explicit stable identifier,
    finite connect/keepalive/inflight/packet bounds, clean-start and session
    expiry policy, verified TLS material, and a bounded Last Will. Reconnect is
    always disabled; a new Runtime subscription must resolve credentials again.
    """

    @behaviour Wotex.Binding.MQTT.Client

    alias Wotex.Binding.MQTT.Topic
    alias Wotex.Lab.Adapters.MQTT.Session
    alias Wotex.Lab.Error
    alias Wotex.Runtime.{Context, ExecutionContext}

    @impl Wotex.Binding.MQTT.Client
    def publish(command, %ExecutionContext{} = execution_context, config) do
      with {:ok, config} <- normalize_config(config),
           {:ok, credential} <- connect_credential(execution_context.credential) do
        Session.publish(command, credential, config, budget(execution_context, config))
      end
    end

    @impl Wotex.Binding.MQTT.Client
    def read(command, timeout, %ExecutionContext{} = execution_context, config)
        when is_integer(timeout) and timeout > 0 do
      with {:ok, config} <- normalize_config(config),
           {:ok, credential} <- connect_credential(execution_context.credential) do
        Session.read(command, credential, config, timeout)
      end
    end

    @impl Wotex.Binding.MQTT.Client
    def subscribe(command, owner, %ExecutionContext{} = execution_context, config)
        when is_pid(owner) do
      with {:ok, config} <- normalize_config(config),
           {:ok, credential} <- connect_credential(execution_context.credential) do
        Session.subscribe(command, credential, config, owner)
      end
    end

    @impl Wotex.Binding.MQTT.Client
    def unsubscribe(session, _command, %ExecutionContext{}, _config) when is_pid(session),
      do: Session.close(session)

    def unsubscribe(_handle, _command, _execution_context, _config),
      do: error(:invalid_handle, "the subscription handle is not a Lab MQTT session")

    defp connect_credential(nil), do: {:ok, []}

    defp connect_credential({:password, user, password})
         when is_binary(user) and is_binary(password),
         do: {:ok, [username: user, password: password]}

    defp connect_credential(credentials) when is_map(credentials) do
      Enum.reduce_while(credentials, {:ok, []}, fn {_name, credential}, {:ok, acc} ->
        case connect_credential(credential) do
          {:ok, options} -> {:cont, {:ok, acc ++ options}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end

    defp connect_credential(_credential),
      do: error(:unsupported_credential, "the resolved credential is not an MQTT one")

    defp budget(%ExecutionContext{context: context}, config) do
      case Context.remaining_ms(Context.deadline(context), clock(Context.deadline(context))) do
        :infinity -> config.connect_timeout
        remaining when is_integer(remaining) and remaining > 0 -> remaining
        _exhausted -> 1
      end
    end

    defp clock(%DateTime{}), do: DateTime.utc_now()
    defp clock(_deadline), do: System.monotonic_time(:millisecond)

    defp normalize_config(config) when is_map(config) or is_list(config) do
      config = Map.new(config)

      normalized = %{
        host: Map.get(config, :host),
        port: Map.get(config, :port),
        client_id_prefix: Map.get(config, :client_id_prefix, "wotex-lab"),
        client_id: Map.get(config, :client_id),
        keepalive: Map.get(config, :keepalive, 30),
        connect_timeout: Map.get(config, :connect_timeout, 5_000),
        clean_start: Map.get(config, :clean_start, true),
        session_expiry_interval: Map.get(config, :session_expiry_interval, 0),
        receive_maximum: Map.get(config, :receive_maximum, 64),
        maximum_packet_size: Map.get(config, :maximum_packet_size, 1_048_576),
        max_inflight: Map.get(config, :max_inflight, 16),
        tls_ca_certfile: Map.get(config, :tls_ca_certfile),
        tls_certfile: Map.get(config, :tls_certfile),
        tls_keyfile: Map.get(config, :tls_keyfile),
        will: Map.get(config, :will)
      }

      allowed = Map.keys(normalized)

      if Enum.all?(Map.keys(config), &(&1 in allowed)) and valid_config?(normalized),
        do: {:ok, normalized},
        else: invalid_config()
    rescue
      _error -> invalid_config()
    end

    defp normalize_config(_config), do: invalid_config()

    defp valid_config?(config) do
      Enum.all?([
        is_nil(config.host) or nonempty_binary?(config.host, 253),
        is_nil(config.port) or integer_in?(config.port, 1..65_535),
        nonempty_binary?(config.client_id_prefix, 64),
        is_nil(config.client_id) or nonempty_binary?(config.client_id, 128),
        integer_in?(config.keepalive, 0..65_535),
        integer_in?(config.connect_timeout, 1..60_000),
        is_boolean(config.clean_start),
        integer_in?(config.session_expiry_interval, 0..4_294_967_295),
        integer_in?(config.receive_maximum, 1..65_535),
        integer_in?(config.maximum_packet_size, 1..16_777_216),
        integer_in?(config.max_inflight, 1..1_024),
        optional_path?(config.tls_ca_certfile),
        optional_path?(config.tls_certfile),
        optional_path?(config.tls_keyfile),
        paired_client_certificate?(config),
        valid_will?(config.will, config.maximum_packet_size),
        stable_session_policy?(config)
      ])
    end

    defp nonempty_binary?(value, limit),
      do: is_binary(value) and byte_size(value) in 1..limit and String.valid?(value)

    defp integer_in?(value, range), do: is_integer(value) and value in range
    defp optional_path?(nil), do: true
    defp optional_path?(value), do: nonempty_binary?(value, 4_096)

    defp paired_client_certificate?(config),
      do: is_nil(config.tls_certfile) == is_nil(config.tls_keyfile)

    defp valid_will?(nil, _maximum_packet_size), do: true

    defp valid_will?(will, maximum_packet_size) when is_map(will) do
      allowed = [:topic, :payload, :qos, :retain, :delay_interval]
      topic = Map.get(will, :topic)
      payload = Map.get(will, :payload)

      Enum.all?([
        Enum.all?(Map.keys(will), &(&1 in allowed)),
        match?(:ok, Topic.validate_name(topic)),
        is_binary(payload) and byte_size(payload) <= maximum_packet_size,
        Map.get(will, :qos, 0) in 0..2,
        is_boolean(Map.get(will, :retain, false)),
        integer_in?(Map.get(will, :delay_interval, 0), 0..4_294_967_295)
      ])
    end

    defp valid_will?(_will, _maximum_packet_size), do: false

    defp stable_session_policy?(
           %{clean_start: clean_start, session_expiry_interval: expiry} = config
         ) do
      if clean_start and expiry == 0, do: true, else: is_binary(config.client_id)
    end

    defp invalid_config,
      do: error(:invalid_mqtt_config, "the MQTT client configuration is invalid")

    defp error(code, message),
      do: {:error, Error.new(code, :transport, message, class: :permanent)}
  end
end
