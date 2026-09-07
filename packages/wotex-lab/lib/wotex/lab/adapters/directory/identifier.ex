defmodule Wotex.Lab.Adapters.Directory.Identifier do
  @moduledoc """
  Deterministic `Wotex.Directory.Identifier` generator.

  State is an `Agent` counter started with `start_link/1`; each call yields
  `urn:wotex:lab:thing:<n>` for anonymous registrations. A host that needs
  globally unique identity supplies its own UUID-backed implementation.
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

  def generate(_state), do: {:error, :invalid_identifier_state}
end
