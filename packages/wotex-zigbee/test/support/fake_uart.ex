defmodule Wotex.Zigbee.TestUART do
  @moduledoc false

  @spec enumerate() :: map()
  def enumerate do
    Agent.get(agent(), & &1.ports)
  end

  @spec start_link() :: Agent.on_start()
  def start_link do
    case Agent.get(agent(), & &1.start_result) do
      :ok ->
        parent = self()
        Agent.start_link(fn -> %{parent: parent, open: false} end)

      {:error, _} = error ->
        error
    end
  end

  @spec open(pid(), binary(), keyword()) :: :ok | {:error, atom()}
  def open(uart, path, options) do
    send(test_pid(), {:uart_open, uart, path, options})

    result = Agent.get(agent(), & &1.open_result)

    if result == :ok do
      Agent.update(uart, &Map.put(&1, :open, true))

      Agent.get_and_update(agent(), fn state ->
        {nil, %{state | ports: Map.get(state, :ports_after_open, state.ports)}}
      end)
    end

    result
  end

  @spec write(pid(), binary()) :: :ok | {:error, atom()}
  def write(uart, bytes) do
    send(test_pid(), {:uart_write, uart, bytes})
    Agent.get(agent(), & &1.write_result)
  end

  @spec close(pid()) :: :ok
  def close(uart) do
    send(test_pid(), {:uart_close, uart})
    :ok
  end

  @spec stop(pid()) :: :ok
  def stop(uart) do
    Agent.stop(uart)
  end

  @spec start_fixture(pid(), map(), keyword()) :: pid()
  def start_fixture(test, ports, options \\ []) do
    {:ok, fixture} =
      Agent.start(fn ->
        %{
          test: test,
          ports: ports,
          ports_after_open: Keyword.get(options, :ports_after_open, ports),
          start_result: Keyword.get(options, :start_result, :ok),
          open_result: Keyword.get(options, :open_result, :ok),
          write_result: Keyword.get(options, :write_result, :ok)
        }
      end)

    :persistent_term.put({__MODULE__, :fixture}, fixture)
    fixture
  end

  @spec stop_fixture(pid()) :: :ok
  def stop_fixture(fixture) do
    :persistent_term.erase({__MODULE__, :fixture})
    Agent.stop(fixture)
  end

  defp agent, do: :persistent_term.get({__MODULE__, :fixture})
  defp test_pid, do: Agent.get(agent(), & &1.test)
end
