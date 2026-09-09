defmodule Wotex.Binding.MQTT.Test.FakeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(security, _, context, config) do
    send(config.test_pid, {:credentials, security, context.request_id})
    {:ok, :ephemeral_credential}
  end
end
