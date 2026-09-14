defmodule Wotex.Matter.RuntimeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(
        %{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}},
        form,
        context,
        %{test_pid: test_pid}
      ) do
    send(test_pid, {:matter_credentials, Wotex.Form.to_map(form), context.request_id})
    {:ok, nil}
  end

  def resolve(_, _, _, _) do
    {:error, Wotex.Matter.Error.new(:unsupported_security)}
  end
end
