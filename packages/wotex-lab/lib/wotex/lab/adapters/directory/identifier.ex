# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Directory.Repository) do
  defmodule Wotex.Lab.Adapters.Directory.Identifier do
    @moduledoc """
    Deterministic `Wotex.Directory.Identifier` generator.

    State is an `Agent` counter started with `start_link/1`; each call yields
    `urn:wotex:lab:thing:<n>` for anonymous registrations. A host that needs
    globally unique identity supplies its own UUID-backed implementation.

    The counter begins at zero and increments atomically for each successful
    generation call. A caller may supply a different prefix, although the
    resulting string must still satisfy `Wotex.Directory.Identifier.valid?/1`
    when used by the directory.

    Identity is local to the lifetime and ownership of the agent. Restarting
    it resets the sequence, and two agents may issue the same value; repository
    collision handling therefore remains authoritative. This adapter is
    intended for deterministic simulations and fixtures, not distributed name
    allocation.
    """

    @behaviour Wotex.Directory.Identifier

    @doc "Starts a counter; `prefix` defaults to `urn:wotex:lab:thing:`."
    @spec start_link(String.t()) :: Agent.on_start()
    def start_link(prefix \\ "urn:wotex:lab:thing:") when is_binary(prefix),
      do: Agent.start_link(fn -> {prefix, 0} end)

    @impl Wotex.Directory.Identifier
    def generate(agent) when is_pid(agent) do
      {:ok,
       Agent.get_and_update(agent, fn {prefix, n} ->
         {prefix <> Integer.to_string(n + 1), {prefix, n + 1}}
       end)}
    end

    def generate(_), do: {:error, :invalid_identifier_state}
  end
end
