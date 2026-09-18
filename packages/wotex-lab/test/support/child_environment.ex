defmodule Wotex.Lab.Test.ChildEnvironment do
  @moduledoc false

  # Environment for the operating-system children the suite spawns.
  # `cleared/0` passes nothing on and suits signal and process utilities that
  # need no environment. `scrubbed/0` keeps the contributor's toolchain
  # environment (paths, locale, Docker and cargo homes) but clears every
  # variable whose name carries a credential by convention, so a token in the
  # shell that runs the suite never reaches docker, cargo, elixir or git.

  @credential ~r/TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|CREDENTIAL/

  @spec cleared() :: [{String.t(), nil}]
  def cleared, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  @spec scrubbed() :: [{String.t(), nil}]
  def scrubbed do
    for {name, _} <- System.get_env(), Regex.match?(@credential, name), do: {name, nil}
  end
end
