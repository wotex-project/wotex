defmodule Wotex.Runtime.Test.FakeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(security, form, context, %{test_pid: test_pid} = config) do
    secret = Map.get(config, :secret, "credential-material")
    send(test_pid, {:credentials, security, form, context.request_id})

    case Map.get(config, :mode, :ok) do
      :ok -> {:ok, secret}
      :error -> {:error, {:credential_error, secret}}
      :invalid -> :invalid
    end
  end
end
