defmodule Wotex.Directory.TestAuthorization do
  @moduledoc false

  @behaviour Wotex.Directory.Authorization

  @impl true
  def authorize(state, principal, operation, target, context) do
    notify(state, {:authorize, principal, operation, target, context})

    default = Map.get(state, :result, :ok)
    state |> Map.get(:results, %{}) |> Map.get({operation, target}, default)
  end

  defp notify(%{test_pid: test_pid}, event) when is_pid(test_pid), do: send(test_pid, event)
  defp notify(_state, _event), do: :ok
end
