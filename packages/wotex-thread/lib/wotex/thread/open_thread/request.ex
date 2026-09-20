defmodule Wotex.Thread.OpenThread.Request do
  @moduledoc """
  Maps the admitted Thread operation set to native bridge commands.

  Exact request shapes select inspection, Dataset operations, enablement,
  network formation, management updates and commissioner admissions. Dataset
  and joiner helpers revalidate their values before parameters are produced.
  Unsupported operations and extra fields return a structured error before
  native submission; arbitrary daemon command text is never accepted.

  The connection uses the mutation classification to distinguish an unsent
  failure from an uncertain effect after submission. Admission replies also
  must echo the requested identity and lifetime. This module performs no I/O,
  allocates no request identity and owns neither deadlines nor retry policy.
  """

  alias Wotex.Thread.{Error, JoinerAdmission, JoinerConfig, JoinerIdentity}
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

  def encode(%{type: :joiner_start, config: config} = request) when map_size(request) == 2 do
    with {:ok, parameters} <- JoinerConfig.parameters(config),
         do: {:ok, {"joiner_start", parameters}}
  end

  def encode(%{type: :joiner_stop} = request) when map_size(request) == 1,
    do: {:ok, {"joiner_stop", %{}}}

  def encode(%{type: :subscribe_state, queue_limit: limit} = request)
      when map_size(request) == 2 and is_integer(limit) and limit in 1..10_000,
      do: {:ok, {"subscribe_state", %{queue_limit: limit}}}

  def encode(%{type: :unsubscribe, subscription_id: id, generation: generation} = request)
      when map_size(request) == 3 and is_binary(id) and byte_size(id) in 1..128 and
             is_integer(generation) and generation in 1..0xFFFFFFFFFFFFFFFE,
      do: {:ok, {"unsubscribe", %{subscription_id: id, generation: generation}}}

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
             "remove_joiner",
             "joiner_start",
             "joiner_stop"
           ],
      do: true

  def mutation?(_), do: false
end
