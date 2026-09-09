defmodule Wotex.BLE.RuntimeErrorPort do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, Wotex.BLE.Error.new(:unsupported_security)}

  @impl Wotex.Runtime.Transport
  def request(_, _, error), do: {:error, error}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, :not_supported}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, :not_supported}
end
