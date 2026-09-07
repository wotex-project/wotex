defmodule Wotex.Lab.Adapters.Directory.Authorization do
  @moduledoc """
  Explicit `Wotex.Directory.Authorization` policies for simulations.

  State `:allow_all` permits every operation and is confined to disposable
  simulations. State `%{principal => [operation]}` is a scoped policy: a
  principal absent from the map, or an operation absent from its list, is
  denied before any repository access. A tenant may be bound by placing it in
  the request context's `authorization` value; when the policy carries a
  `{:tenant, name}` requirement the context must match it.
  """

  @behaviour Wotex.Directory.Authorization

  @impl Wotex.Directory.Authorization
  def authorize(:allow_all, _principal, _operation, _target, _context), do: :ok

  def authorize(policy, principal, operation, _target, context) when is_map(policy) do
    case Map.get(policy, principal) do
      nil -> :deny
      allowed -> decide(allowed, operation, context)
    end
  end

  def authorize(_policy, _principal, _operation, _target, _context),
    do: {:error, :invalid_policy}

  defp decide({:tenant, tenant, operations}, operation, {:tenant, tenant}),
    do: decide(operations, operation, nil)

  defp decide({:tenant, _tenant, _operations}, _operation, _context), do: :deny

  defp decide(operations, operation, _context) when is_list(operations) do
    if operation in operations, do: :ok, else: :deny
  end
end
