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

    Configuration is non-secret. `:host` is an optional admitted-peer pin that
    the Form's broker host must match, `:port` (1883) is the port for a Form
    href without one, `:client_id_prefix` (`"wotex-lab"`) prefixes a random
    Client Identifier, `:keepalive` (30) is the MQTT Keep Alive in seconds and
    `:connect_timeout` (5,000) bounds the connect exchange in milliseconds.
    """

    @behaviour Wotex.Binding.MQTT.Client

    alias Wotex.Lab.Adapters.MQTT.Session
    alias Wotex.Lab.Error
    alias Wotex.Runtime.{Context, ExecutionContext}

    @impl Wotex.Binding.MQTT.Client
    def publish(command, %ExecutionContext{} = execution_context, config) do
      config = normalize_config(config)

      with {:ok, credential} <- connect_credential(execution_context.credential) do
        Session.publish(command, credential, config, budget(execution_context, config))
      end
    end

    @impl Wotex.Binding.MQTT.Client
    def read(command, timeout, %ExecutionContext{} = execution_context, config)
        when is_integer(timeout) and timeout > 0 do
      config = normalize_config(config)

      with {:ok, credential} <- connect_credential(execution_context.credential) do
        Session.read(command, credential, config, timeout)
      end
    end

    @impl Wotex.Binding.MQTT.Client
    def subscribe(command, owner, %ExecutionContext{} = execution_context, config)
        when is_pid(owner) do
      config = normalize_config(config)

      with {:ok, credential} <- connect_credential(execution_context.credential) do
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

      %{
        host: Map.get(config, :host),
        port: Map.get(config, :port, 1883),
        client_id_prefix: Map.get(config, :client_id_prefix, "wotex-lab"),
        keepalive: Map.get(config, :keepalive, 30),
        connect_timeout: Map.get(config, :connect_timeout, 5_000)
      }
    end

    defp normalize_config(_config), do: normalize_config(%{})

    defp error(code, message),
      do: {:error, Error.new(code, :transport, message, class: :permanent)}
  end
end
