defmodule Wotex.Lab.Check.ChildEnvironment do
  @moduledoc false

  # Environment for the operating-system children the check scripts spawn.
  # `cleared/0` passes nothing on and suits utilities that need no environment
  # (`id`, `kill`). `scrubbed/0` keeps the contributor's toolchain environment
  # (paths, locale, Hex, Docker and cargo homes) but clears every variable
  # whose name carries a credential by convention, so a token in the shell that
  # runs a gate never reaches git, docker, tar, mix, node or npm.

  @credential ~r/TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|CREDENTIAL/

  @spec cleared() :: [{String.t(), nil}]
  def cleared, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  @spec scrubbed() :: [{String.t(), nil}]
  def scrubbed do
    for {name, _} <- System.get_env(), Regex.match?(@credential, name), do: {name, nil}
  end
end
