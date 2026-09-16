defmodule Wotex.Matter.Native.ProcessCommand do
  @moduledoc false

  @doc false
  @spec run(String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def run(command, arguments, options \\ []) do
    cleared = for {name, _} <- System.get_env(), do: {name, nil}
    System.cmd(command, arguments, Keyword.put(options, :env, cleared))
  end
end
