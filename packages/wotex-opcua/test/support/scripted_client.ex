defmodule Wotex.OPCUA.TestScriptedClient do
  @moduledoc false

  @behaviour Wotex.OPCUA.Client

  # Replies with the configured peer value and reports each call to the test.
  @impl Wotex.OPCUA.Client
  def connect(opts) do
    test = Keyword.fetch!(opts, :test)
    send(test, {:scripted, :connect})
    {:ok, %{test: test, reply: Keyword.fetch!(opts, :reply)}}
  end

  @impl Wotex.OPCUA.Client
  def request(handle, message, _) do
    send(handle.test, {:scripted, {:request, message}})
    {:ok, handle.reply}
  end

  @impl Wotex.OPCUA.Client
  def disconnect(handle) do
    send(handle.test, {:scripted, :disconnect})
    :ok
  end
end
