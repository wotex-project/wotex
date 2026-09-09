# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Directory.Repository) do
  defmodule Wotex.Lab.Adapters.Directory.Authorization do
    @moduledoc """
    Explicit `Wotex.Directory.Authorization` policies for simulations.

    State `:allow_all` permits every operation and is confined to disposable
    simulations. State `%{principal => [operation]}` is a scoped policy: a
    principal absent from the map, or an operation absent from its list, is
    denied before any repository access. A tenant may be bound by placing it in
    the request context's `authorization` value; when the policy carries a
    `{:tenant, name, operations}` requirement the context must match it.

    The adapter returns `:ok` or `:deny` for admitted policies and
    `{:error, :invalid_policy}` for an unsupported top-level policy. It performs
    no identity verification, tenant lookup, or repository access, which keeps
    authentication and policy distribution under host
    ownership.
    """

    @behaviour Wotex.Directory.Authorization

    @impl Wotex.Directory.Authorization
    def authorize(:allow_all, _, _, _, _), do: :ok

    def authorize(policy, principal, operation, _, context) when is_map(policy) do
      case Map.get(policy, principal) do
        nil -> :deny
        allowed -> decide(allowed, operation, context)
      end
    end

    def authorize(_, _, _, _, _),
      do: {:error, :invalid_policy}

    defp decide({:tenant, tenant, operations}, operation, {:tenant, tenant}),
      do: decide(operations, operation, nil)

    defp decide({:tenant, _, _}, _, _), do: :deny

    defp decide(operations, operation, _) when is_list(operations) do
      if operation in operations, do: :ok, else: :deny
    end
  end
end
