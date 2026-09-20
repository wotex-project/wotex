defmodule Wotex.Thread.RuntimeClient do
  @moduledoc false

  @behaviour Wotex.Thread.Client

  @impl Wotex.Thread.Client
  def connect(options) do
    receiver = Keyword.fetch!(options, :test_pid)
    send(receiver, {:runtime_client, :open, Keyword.fetch!(options, :timeout)})
    Process.sleep(Keyword.get(options, :connect_delay, 0))

    {:ok,
     %{
       receiver: receiver,
       reply: Keyword.fetch!(options, :peer_reply),
       request_delay: Keyword.get(options, :request_delay, 0)
     }}
  end

  @impl Wotex.Thread.Client
  def request(handle, message, timeout) do
    send(handle.receiver, {:runtime_client, :request, message, timeout})
    Process.sleep(handle.request_delay)

    case handle.reply do
      {:error, _} = error -> error
      value -> {:ok, value}
    end
  end

  @impl Wotex.Thread.Client
  def disconnect(handle) do
    send(handle.receiver, {:runtime_client, :close})
    :ok
  end
end
