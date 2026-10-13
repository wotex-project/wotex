defmodule Mix.Tasks.Wotex.Profiles.Validate do
  @shortdoc "Validate a profile bundle against an explicit contract"
  @moduledoc "Validate an explicitly supplied contract and candidate with optional capture; exit 0/1/2 for compatible/invalid/failure."
  use Mix.Task
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(arguments) do
    {status, bytes} = Wotex.Profiles.CLI.execute(:validate, arguments)
    IO.write([bytes, "\n"])
    if status != 0, do: System.halt(status)
    :ok
  end
end
