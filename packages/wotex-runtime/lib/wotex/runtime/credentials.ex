defmodule Wotex.Runtime.Credentials do
  @moduledoc """
  Port for resolving credential material immediately before a transport call.

  The first argument contains only selected TD security names and definitions;
  the Form and caller context provide the remaining lookup scope. An
  implementation returns credential material for one immediate execution
  context. It should not mutate the Thing Description or place secrets in
  errors, metadata, global configuration, or process names.

  Credential custody, rotation, auditing, and provider access remain entirely
  consumer-owned. The runtime stores only the behaviour module and its opaque
  configuration.
  """

  alias Wotex.Form
  alias Wotex.Runtime.Context

  @typedoc "Consumer-owned credential-provider configuration."
  @type config :: term()

  @doc "Resolves credential material for one selected Form and interaction."
  @callback resolve(map(), Form.t(), Context.t(), config()) ::
              {:ok, term()} | {:error, term()}
end
