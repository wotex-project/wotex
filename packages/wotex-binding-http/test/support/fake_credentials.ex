defmodule Wotex.Binding.HTTP.Test.FakeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  @spec resolve(term(), term(), term(), map()) :: {:ok, term()}
  def resolve(security, form, context, config) do
    send(config.owner, {:credential_resolve, security, form, context})
    {:ok, config.credential}
  end
end
