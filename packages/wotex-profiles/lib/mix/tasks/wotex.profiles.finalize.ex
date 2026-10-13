defmodule Mix.Tasks.Wotex.Profiles.Finalize do
  @shortdoc "Finalize a profile draft against an explicit contract"
  @moduledoc "Finalize an explicit local-reference draft under an explicit contract and write only its successful derived bundle."
  use Mix.Task
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(arguments) do
    {status, bytes} = Wotex.Profiles.CLI.execute(:finalize, arguments)
    IO.write([bytes, "\n"])
    if status != 0, do: System.halt(status)
    :ok
  end
end
