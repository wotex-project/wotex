defmodule Wotex.Zigbee.TestKeyCredentials do
  @moduledoc false

  @behaviour Wotex.Zigbee.Credentials

  @spec start(pid(), keyword()) :: {pid(), binary()}
  def start(test, options) do
    key = :crypto.strong_rand_bytes(16)
    {spawn(fn -> loop(test, key, options) end), key}
  end

  @impl Wotex.Zigbee.Credentials
  def authorize(handle, context, budget) do
    {_, options} = request(handle, {:authorize, context, budget}, budget)

    case Keyword.get(options, context.phase, :allow) do
      :allow ->
        {:ok, context.deadline_ms}

      :deny ->
        {:error, "credential-canary"}

      :raise ->
        raise ArgumentError, "credential-canary"

      {:horizon, margin} ->
        {:ok, context.now_ms + margin}

      {:delay, milliseconds} ->
        Process.sleep(milliseconds)
        {:ok, context.deadline_ms}
    end
  end

  @impl Wotex.Zigbee.Credentials
  def with_network_key(handle, context, budget, consume) do
    {key, options} = request(handle, {:key, context, budget}, budget)
    behavior = Keyword.get(options, :key, :allow)

    use_key(behavior, key, consume, options)
  end

  defp use_key(:allow, key, consume, _), do: consume.(key)
  defp use_key(:deny, _, _, _), do: {:error, "credential-canary"}
  defp use_key(:raise, _, _, _), do: raise(ArgumentError, "credential-canary")
  defp use_key(:throw, _, _, _), do: throw("credential-canary")
  defp use_key(:exit, _, _, _), do: exit("credential-canary")
  defp use_key(:no_call, _, _, _), do: :ok
  defp use_key(:bad_return, key, _, _), do: %{key: key, text: "credential-canary"}
  defp use_key(:bad_key, key, consume, _), do: consume.(binary_part(key, 0, 15))
  defp use_key(:zero_key, _, consume, _), do: consume.(<<0::128>>)
  defp use_key(:ff_key, _, consume, _), do: consume.(<<0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF::128>>)

  defp use_key(:multiple, key, consume, _) do
    consume.(key)
    consume.(key)
    :ok
  end

  defp use_key(:foreign, key, consume, _) do
    owner = self()
    reference = make_ref()
    spawn(fn -> send(owner, {reference, consume.(key)}) end)

    receive do
      {^reference, {:error, :credentials}} -> :ok
    end
  end

  defp use_key(:save, key, consume, options) do
    send(Keyword.fetch!(options, :test_pid), {:saved_consumer_write, consume, key})
    :ok
  end

  defp use_key(:raise_after, key, consume, _) do
    :ok = consume.(key)
    raise ArgumentError, "credential-canary"
  end

  defp use_key({:delay, milliseconds}, key, consume, _) do
    Process.sleep(milliseconds)
    consume.(key)
  end

  defp use_key({:delay_after, milliseconds}, key, consume, _) do
    :ok = consume.(key)
    Process.sleep(milliseconds)
    :ok
  end

  defp request(handle, message, budget) do
    reference = make_ref()
    send(handle, {:request, self(), reference, message})

    receive do
      {^reference, key, options} -> {key, options}
    after
      budget -> exit({:timeout, "credential-canary"})
    end
  end

  defp loop(test, key, options) do
    receive do
      {:request, caller, reference, {kind, context, budget}} ->
        send(test, {:key_custody, kind, context, budget})
        send(caller, {reference, key, Keyword.put(options, :test_pid, test)})
        loop(test, key, options)

      :stop ->
        :ok
    end
  end
end
