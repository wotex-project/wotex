defmodule Wotex.Lab.Test.BlockingServing do
  @moduledoc false

  @behaviour Nx.Serving

  @impl Nx.Serving
  def init(_, observer, _), do: {:ok, observer}

  @impl Nx.Serving
  def handle_batch(batch, _, observer) do
    execute = fn ->
      send(observer, {:serving_execution, self()})

      receive do
        :release ->
          output = Nx.Defn.jit_apply(&Function.identity/1, [batch], compiler: Nx.Defn.Evaluator)
          {output, %{released: true}}
      end
    end

    {:execute, execute, observer}
  end
end
