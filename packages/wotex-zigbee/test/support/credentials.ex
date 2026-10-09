defmodule Wotex.Zigbee.TestCredentials do
  @moduledoc false

  @behaviour Wotex.Zigbee.Credentials

  @spec start(pid(), term()) :: pid()
  def start(test_pid, behavior) do
    spawn(fn -> loop(test_pid, behavior) end)
  end

  @impl Wotex.Zigbee.Credentials
  def authorize(handle, context, budget) do
    reference = make_ref()
    send(handle, {:authorize, self(), reference, context, budget})

    receive do
      {^reference, behavior} -> respond(behavior, context)
    after
      budget -> exit({:timeout, "credential-canary"})
    end
  end

  defp respond(:allow, context),
    do: {:ok, context.deadline_ms + Map.get(context.request, :duration_s, 0) * 1_000}

  defp respond(:deny, _), do: {:error, "credential-canary"}
  defp respond(:raise, _), do: raise(ArgumentError, "credential-canary")
  defp respond(:throw, _), do: throw("credential-canary")
  defp respond(:exit, _), do: exit("credential-canary")
  defp respond(:malformed, _), do: %{key: "credential-canary"}
  defp respond(:bad_horizon, _), do: {:ok, "credential-canary"}
  defp respond(:huge_horizon, _), do: {:ok, 0x8000000000000000}

  defp respond({:horizon, margin}, context),
    do: {:ok, context.now_ms + Map.get(context.request, :duration_s, 0) * 1_000 + margin}

  defp respond({:delay, milliseconds}, context) do
    Process.sleep(milliseconds)
    respond(:allow, context)
  end

  defp loop(test_pid, behavior) do
    receive do
      {:authorize, caller, reference, context, budget} ->
        send(test_pid, {:credential_request, self(), context, budget})
        send(caller, {reference, behavior})
        loop(test_pid, behavior)

      :stop ->
        :ok
    end
  end
end
