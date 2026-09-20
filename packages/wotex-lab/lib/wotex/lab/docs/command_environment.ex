defmodule Wotex.Lab.Docs.CommandEnvironment do
  @moduledoc false

  @credential ~r/TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|CREDENTIAL/

  @doc false
  @spec scrubbed([{String.t(), String.t() | nil}]) :: [{String.t(), String.t() | nil}]
  def scrubbed(extra \\ []) do
    cleared =
      for {name, _} <- System.get_env(), Regex.match?(@credential, name), do: {name, nil}

    cleared ++ [{"GIT_ASKPASS", nil}, {"GIT_TERMINAL_PROMPT", "0"} | extra]
  end
end
