defmodule ArchiveWriteClient do
  @moduledoc false

  @behaviour Wotex.BLE.Client
  @impl Wotex.BLE.Client
  def connect(options) do
    receiver = Keyword.fetch!(options, :receiver)
    send(receiver, {:client_open, Keyword.fetch!(options, :timeout)})
    {:ok, %{receiver: receiver, reply: Keyword.fetch!(options, :reply)}}
  end

  @impl Wotex.BLE.Client
  def request(handle, message, timeout) do
    send(handle.receiver, {:client_request, message, timeout})
    {:ok, handle.reply}
  end

  @impl Wotex.BLE.Client
  def disconnect(handle) do
    send(handle.receiver, :client_closed)
    :ok
  end
end

defmodule ArchiveWriteCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, :unsupported_security}
end
