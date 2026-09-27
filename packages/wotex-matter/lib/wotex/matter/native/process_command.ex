defmodule Wotex.Matter.Native.ProcessCommand do
  @moduledoc """
  Executes first-party native helper commands without the host environment.

  The command receives only arguments and options supplied by its caller.
  Clearing inherited variables keeps unrelated credentials, product settings
  and build configuration out of native child processes. Callers still own
  command selection, argument validation and output bounds.
  """

  @doc "Runs a command with inherited environment variables cleared."
  @spec run(String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def run(command, arguments, options \\ []) do
    cleared = for {name, _} <- System.get_env(), do: {name, nil}
    System.cmd(command, arguments, Keyword.put(options, :env, cleared))
  end
end
