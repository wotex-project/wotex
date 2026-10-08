defmodule Wotex.Modbus.RegisterProcessDriver do
  @moduledoc false

  @behaviour Wotex.Modbus.RegisterCodec.Driver
  use GenServer
  alias Wotex.Modbus.RegisterCodec
  alias Wotex.Runtime.Codec.Wire

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl Wotex.Modbus.RegisterCodec.Driver
  def profile(config), do: callback(config, :profile, fn -> {:ok, config.profile} end)
  @impl Wotex.Modbus.RegisterCodec.Driver
  def open(host, owner, channel, plan, limits, config),
    do:
      callback(config, :open, fn ->
        GenServer.call(config.profile.pid, {:open, host, owner, channel, plan, limits})
      end)

  @impl Wotex.Modbus.RegisterCodec.Driver
  def write(channel, bytes, config),
    do:
      callback(config, :write, fn ->
        GenServer.call(config.profile.pid, {:write, channel, bytes})
      end)

  @impl Wotex.Modbus.RegisterCodec.Driver
  def close(channel, ms, config),
    do:
      callback(config, :close, fn -> GenServer.call(config.profile.pid, {:close, channel, ms}) end)

  defp callback(config, name, default) do
    case Map.get(Map.get(config, :returns, %{}), name, :default) do
      :default -> default.()
      :raise -> raise "driver-secret-canary"
      :throw -> throw("driver-secret-canary")
      :exit -> exit("driver-secret-canary")
      result -> result
    end
  end

  @impl GenServer
  def init(opts),
    do:
      {:ok,
       Map.merge(
         %{
           mode: :normal,
           cleanup: :confirmed_local,
           observer: nil,
           host: nil,
           channel: nil,
           resources: false,
           hello: nil
         },
         opts
       )}

  @impl GenServer
  def handle_call({:open, host, owner, channel, plan, limits}, _, %{host: nil} = state) do
    state =
      Map.merge(state, %{
        host: host,
        channel: channel,
        host_ref: Process.monitor(host),
        owner_ref: Process.monitor(owner),
        resources: true,
        plan: plan,
        limits: limits
      })

    notify(state, {:claimed, self(), host, channel})
    if state.mode != :hold_open, do: send(host, {:wotex_modbus_codec, channel, :opened})
    {:reply, :ok, state}
  end

  def handle_call({:open, _, _, _, _, _}, _, state), do: {:reply, {:error, :overloaded}, state}

  def handle_call({:write, channel, bytes}, _, %{channel: channel} = state) do
    {:ok, frame} = Wire.decode(bytes)
    notify(state, {:write, self(), frame["type"], frame["seq"]})
    {:reply, :ok, state, {:continue, {:frame, frame}}}
  end

  def handle_call({:write, _, _}, _, state), do: {:reply, {:error, :codec_unavailable}, state}

  def handle_call({:close, channel, ms}, _, state) do
    notify(state, {:close, self(), channel, ms})

    if channel == state.channel do
      state = %{state | resources: false}

      if state.cleanup != :hang,
        do: send(state.host, {:wotex_modbus_codec, channel, {:closed, state.cleanup}})

      {:reply, :ok, state}
    else
      {:reply, {:error, :cleanup_unconfirmed}, state}
    end
  end

  def handle_call({:emit, event}, _, state) do
    send(state.host, {:wotex_modbus_codec, state.channel, event})
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _, state), do: {:reply, state, state}
  def handle_call({:mode, mode}, _, state), do: {:reply, :ok, %{state | mode: mode}}

  @impl GenServer
  def handle_continue({:frame, %{"type" => "hello"} = frame}, state) do
    ready =
      frame
      |> Map.delete("configuration")
      |> Map.put("type", "ready")

    state = %{state | hello: frame}

    unless state.mode == :manual_ready do
      ready =
        if state.mode == :wrong_ready, do: Map.update!(ready, "generation", &(&1 + 1)), else: ready

      emit_frame(state, ready)
    end

    {:noreply, state}
  end

  def handle_continue({:frame, %{"type" => "decode"} = frame}, state) do
    unless state.mode == :manual_decode do
      {:ok, bytes} = Base.decode64(frame["bytes"]["base64"])

      output =
        case RegisterCodec.decode(bytes, frame["metadata"], state.hello["configuration"]) do
          {:ok, node} ->
            %{
              "v" => 1,
              "type" => "result",
              "seq" => frame["seq"],
              "request_id" => frame["request_id"],
              "value" => node
            }

          {:error, code} ->
            %{
              "v" => 1,
              "type" => "refusal",
              "seq" => frame["seq"],
              "request_id" => frame["request_id"],
              "code" => Atom.to_string(code)
            }
        end

      output = if state.mode == :wrong_seq, do: Map.update!(output, "seq", &(&1 + 1)), else: output

      output =
        if state.mode == :wrong_request,
          do: Map.put(output, "request_id", "substituted"),
          else: output

      emit_frame(state, output)
    end

    {:noreply, state}
  end

  def handle_continue({:frame, %{"type" => "stop"}}, state), do: {:noreply, state}

  defp emit_frame(state, frame) do
    {:ok, bytes} = Wire.encode(frame)

    case state.mode do
      :fragment ->
        size = div(byte_size(bytes), 2)
        <<left::binary-size(^size), right::binary>> = bytes
        send(state.host, {:wotex_modbus_codec, state.channel, {:stdout, left}})
        send(state.host, {:wotex_modbus_codec, state.channel, {:stdout, right}})

      :double_reply ->
        send(state.host, {:wotex_modbus_codec, state.channel, {:stdout, bytes <> bytes}})

      :partial_tail ->
        send(state.host, {:wotex_modbus_codec, state.channel, {:stdout, bytes <> "{"}})

      _ ->
        send(state.host, {:wotex_modbus_codec, state.channel, {:stdout, bytes}})
    end
  end

  defp notify(%{observer: nil}, _), do: :ok
  defp notify(state, event), do: send(state.observer, event)

  @impl GenServer
  def handle_info({:DOWN, _, :process, _, _}, state) do
    notify(state, {:custody_released, self()})
    {:noreply, %{state | resources: false}}
  end

  def handle_info(_, state), do: {:noreply, state}
end
