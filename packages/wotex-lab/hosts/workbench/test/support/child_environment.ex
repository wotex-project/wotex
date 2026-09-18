defmodule WotexLabWorkbench.Test.ChildEnvironment do
  @moduledoc false

  # Environment for the Docker children of the explicit Workbench lanes. It
  # keeps the contributor's toolchain environment (paths, locale, Docker home)
  # but clears every variable whose name carries a credential by convention,
  # so a token in the shell that runs the suite never reaches docker.

  @credential ~r/TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|CREDENTIAL/

  @doc false
  @spec scrubbed() :: [{String.t(), nil}]
  def scrubbed do
    for {name, _} <- System.get_env(), Regex.match?(@credential, name), do: {name, nil}
  end
end
