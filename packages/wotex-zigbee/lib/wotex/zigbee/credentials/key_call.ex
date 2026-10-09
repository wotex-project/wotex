defmodule Wotex.Zigbee.Credentials.KeyCall do
  @moduledoc false

  alias Wotex.Zigbee.{Credentials, Error}

  @doc false
  @spec dispatch(
          Credentials.t(),
          Credentials.rotation_context(),
          pos_integer(),
          integer(),
          pid(),
          (binary() -> :ok | {:refused | :failed, Error.kind()})
        ) ::
          :ok | {:refused | :failed, Error.kind()}
  def dispatch(port, context, budget, deadline, caller, write) do
    owner = self()
    marker = {__MODULE__, make_ref()}
    Process.put(marker, %{used: false, attempted: false, result: nil, misuse: false})

    consume = fn key -> consume(marker, owner, caller, deadline, key, write) end
    returned = invoke(port, context, budget, consume)
    state = Process.delete(marker)

    if System.monotonic_time(:millisecond) >= deadline,
      do: fault(state, :timeout),
      else: finish(state, returned)
  end

  defp invoke(port, context, budget, consume) do
    module = port.module

    case module.with_network_key(port.handle, context, budget, consume) do
      :ok -> :ok
      {:error, _} -> :denied
      _ -> :fault
    end
  rescue
    _ -> :fault
  catch
    _, _ -> :fault
  end

  defp consume(marker, owner, caller, deadline, key, write) do
    if self() == owner and is_map(Process.get(marker)) do
      consume_once(marker, caller, deadline, key, write)
    else
      {:error, :credentials}
    end
  end

  defp consume_once(marker, caller, deadline, key, write) do
    state = Process.get(marker)

    cond do
      state.used ->
        Process.put(marker, %{state | misuse: true})
        {:error, :credentials}

      not Process.alive?(caller) ->
        refuse(marker, state, :coordinator_lost)

      System.monotonic_time(:millisecond) >= deadline ->
        refuse(marker, state, :timeout)

      not valid_key?(key) ->
        refuse(marker, state, :credentials)

      true ->
        Process.put(marker, %{state | used: true, attempted: true})
        result = write.(key)

        Process.put(marker, %{
          state
          | used: true,
            attempted: result != {:refused, :timeout},
            result: result
        })

        if result == :ok, do: :ok, else: {:error, :credentials}
    end
  end

  defp refuse(marker, state, kind) do
    Process.put(marker, %{state | used: true, result: {:refused, kind}})
    {:error, kind}
  end

  defp finish(%{misuse: true} = state, _), do: fault(state, :credentials)
  defp finish(%{result: {:failed, kind}}, _), do: {:failed, kind}
  defp finish(%{result: {:refused, kind}}, _), do: {:refused, kind}
  defp finish(%{used: true, result: :ok}, :ok), do: :ok
  defp finish(state, :denied), do: fault(state, :credential_denied)
  defp finish(state, _), do: fault(state, :credentials)

  defp fault(%{attempted: true}, kind), do: {:failed, kind}
  defp fault(_, kind), do: {:refused, kind}
  defp valid_key?(<<key::128>>), do: key not in [0, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF]
  defp valid_key?(_), do: false
end
