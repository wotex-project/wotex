defmodule Wotex.Zigbee.Credentials.PortCall do
  @moduledoc false

  alias Wotex.Zigbee.Credentials

  @max_time 0x7FFFFFFFFFFFFFFF

  @doc false
  @spec authorize(Credentials.t(), Credentials.context(), pos_integer()) ::
          {:ok, integer()} | {:error, :credentials | :credential_denied}
  def authorize(port, context, budget) do
    module = port.module

    case module.authorize(port.handle, context, budget) do
      {:ok, horizon}
      when is_integer(horizon) and horizon >= -@max_time - 1 and horizon <= @max_time ->
        {:ok, horizon}

      {:error, _} ->
        {:error, :credential_denied}

      _ ->
        {:error, :credentials}
    end
  rescue
    _ -> {:error, :credentials}
  catch
    _, _ -> {:error, :credentials}
  end
end
