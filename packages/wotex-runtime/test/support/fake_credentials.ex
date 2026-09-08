defmodule Wotex.Runtime.Test.FakeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(security, form, context, %{test_pid: test_pid} = config) do
    secret = Map.get(config, :secret, "credential-material")
    send(test_pid, {:credentials, security, form, context.request_id})

    mode =
      case Map.get(config, :mode, :ok) do
        {:stop_only, mode} -> if stop_operation?(context, config), do: mode, else: :ok
        mode -> mode
      end

    result(mode, secret)
  end

  defp result(mode, secret) do
    case mode do
      :ok -> {:ok, secret}
      :error -> {:error, {:credential_error, secret}}
      :raise -> raise ArgumentError, "credential defect #{secret}"
      :exit -> exit({:credential_exit, secret})
      :throw -> throw({:credential_throw, secret})
      :invalid -> :invalid
    end
  end

  defp stop_operation?(_context, config) do
    counter = Map.get(config, :counter)
    is_pid(counter) and Agent.get_and_update(counter, &{&1, &1 + 1}) > 0
  end
end
