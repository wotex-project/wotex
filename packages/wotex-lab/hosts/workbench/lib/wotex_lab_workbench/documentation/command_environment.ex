defmodule WotexLabWorkbench.Documentation.CommandEnvironment do
  @moduledoc false

  @sensitive ~w(
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    GITHUB_TOKEN GH_TOKEN HEX_API_KEY NPM_TOKEN NODE_AUTH_TOKEN
    OPENAI_API_KEY ANTHROPIC_API_KEY
  )

  @doc false
  @spec cleared([{String.t(), String.t() | nil}]) :: [{String.t(), String.t() | nil}]
  def cleared(extra \\ []) do
    Enum.map(@sensitive, &{&1, nil}) ++ extra
  end
end
