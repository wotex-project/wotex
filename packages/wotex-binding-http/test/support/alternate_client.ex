defmodule Wotex.Binding.HTTP.Test.AlternateClient do
  @moduledoc false

  @behaviour Wotex.Binding.HTTP.Client

  @impl true
  def request(_request, _credential, _config), do: {:error, :unused}

  @impl true
  def subscribe(_request, _credential, _handler, _config), do: {:error, :unused}

  @impl true
  def close(_handle, _config), do: :ok
end
