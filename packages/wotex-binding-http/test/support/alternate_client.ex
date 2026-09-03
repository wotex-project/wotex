defmodule Wotex.Binding.HTTP.Test.AlternateClient do
  @moduledoc false

  @behaviour Wotex.Binding.HTTP.Client

  @impl Wotex.Binding.HTTP.Client
  @spec request(term(), term(), term()) :: {:error, :unused}
  def request(_, _, _), do: {:error, :unused}

  @impl Wotex.Binding.HTTP.Client
  @spec subscribe(term(), term(), function(), term()) :: {:error, :unused}
  def subscribe(_, _, _, _), do: {:error, :unused}

  @impl Wotex.Binding.HTTP.Client
  @spec close(term(), term()) :: :ok
  def close(_, _), do: :ok
end
