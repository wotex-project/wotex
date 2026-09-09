defmodule Wotex.Directory.TestIdentifier do
  @moduledoc false

  @behaviour Wotex.Directory.Identifier

  @spec start_link([term()]) :: Agent.on_start()
  def start_link(values), do: Agent.start_link(fn -> values end)

  @impl true
  def generate(agent) do
    Agent.get_and_update(agent, fn
      [value | rest] -> {normalize(value), rest}
      [] -> {{:error, :exhausted}, []}
    end)
  end

  defp normalize({:error, _} = error), do: error
  defp normalize(value), do: {:ok, value}
end
