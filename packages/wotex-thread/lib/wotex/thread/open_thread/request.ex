defmodule Wotex.Thread.OpenThread.Request do
  @moduledoc false

  alias Wotex.Thread.{Error, JoinerAdmission, JoinerIdentity}
  alias Wotex.Thread.OpenThread.DatasetWire

  @doc false
  @spec encode(term()) :: {:ok, {String.t(), map()}} | {:error, Error.t()}
  def encode(%{type: type} = request)
      when map_size(request) == 1 and type in [:inspect, :state, :version, :network_name, :rloc16],
      do: {:ok, {Atom.to_string(type), %{}}}

  def encode(%{type: :validate_dataset, dataset: dataset, kind: kind} = request)
      when map_size(request) == 3 do
    with {:ok, parameters} <- DatasetWire.parameters(dataset, kind),
         do: {:ok, {"validate_dataset", parameters}}
  end

  def encode(%{type: :get_dataset, kind: kind} = request) when map_size(request) == 2 do
    with {:ok, parameters} <- DatasetWire.selector(kind), do: {:ok, {"get_dataset", parameters}}
  end

  def encode(%{type: :set_enabled, state: %{ipv6: ipv6, thread: thread} = state} = request)
      when map_size(request) == 2 and map_size(state) == 2 and is_boolean(ipv6) and
             is_boolean(thread) do
    if thread and not ipv6,
      do: {:error, Error.new(:invalid_state)},
      else: {:ok, {"set_enabled", %{ipv6: ipv6, thread: thread}}}
  end

  def encode(%{type: :form_network, dataset: dataset} = request) when map_size(request) == 2 do
    with {:ok, %{dataset: envelope}} <- DatasetWire.parameters(dataset, :active),
         do: {:ok, {"form_network", %{dataset: envelope}}}
  end

  def encode(%{type: type, update: update} = request)
      when map_size(request) == 2 and type in [:management_active_set, :management_pending_set] do
    with {:ok, parameters} <- DatasetWire.management(update),
         do: {:ok, {Atom.to_string(type), parameters}}
  end

  def encode(%{type: type} = request)
      when map_size(request) == 1 and type in [:commissioner_start, :commissioner_stop],
      do: {:ok, {Atom.to_string(type), %{}}}

  def encode(%{type: :add_joiner, admission: admission} = request) when map_size(request) == 2 do
    with {:ok, parameters} <- JoinerAdmission.parameters(admission),
         do: {:ok, {"add_joiner", parameters}}
  end

  def encode(%{type: :remove_joiner, identity: identity} = request) when map_size(request) == 2 do
    with {:ok, identity} <- JoinerIdentity.parameters(identity),
         do: {:ok, {"remove_joiner", %{identity: identity}}}
  end

  def encode(_), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec matches_result?(String.t(), map(), term()) :: boolean()
  def matches_result?("add_joiner", %{identity: identity, lifetime: lifetime}, %{
        identity: actual,
        lifetime_s: lifetime
      }),
      do: JoinerIdentity.parameters(actual) == {:ok, identity}

  def matches_result?("add_joiner", _, _), do: false
  def matches_result?(_, _, _), do: true

  @doc false
  @spec mutation?(term()) :: boolean()
  def mutation?(operation)
      when operation in [
             "set_enabled",
             "form_network",
             "management_active_set",
             "management_pending_set",
             "commissioner_start",
             "commissioner_stop",
             "add_joiner",
             "remove_joiner"
           ],
      do: true

  def mutation?(_), do: false
end
