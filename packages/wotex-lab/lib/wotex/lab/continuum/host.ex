# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(WotexContinuum.Codec) and Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Continuum.Host do
    @moduledoc """
    A simulated consumer host at the cloud end of a continuum channel.

    The host owns admission, correlation and dispatch. It decodes every
    delivery with the bounded continuum codec, acknowledges it on the channel,
    and then decides by kind:

    * a `continuum_manifest` is accepted only when it is compatible with the
      host's schema version and capabilities; until an accepted manifest exists
      every intent from that source is rejected as stale authority;
    * an `observation_proposal` is admitted only for a known Thing and only when
      its `sequence` exceeds the last admitted sequence for that affordance, so
      stale, duplicate and reordered proposals are recorded but never mutate the
      observed state;
    * an `action_intent` is dispatched at most once per idempotency key through
      a runtime `ConsumedThing`, and the outcome is returned to the source as an
      `action_result`; a duplicate delivery produces a duplicate record and no
      second dispatch;
    * every other kind is recorded as received.

    The host keeps its own lifecycle value and refuses intents while draining.
    Received bytes, admitted state, dispatch attempts, results and rejections
    are separately inspectable through `stats/1`.
    """

    use GenServer

    alias Wotex.Lab.Continuum.{Channel, Wire}
    alias Wotex.Runtime.{ConsumedThing, Context}

    alias WotexContinuum.{
      ActionIntent,
      Codec,
      ExecutionScope,
      Lifecycle,
      Manifest,
      Mode,
      ObservationProposal
    }

    @doc false
    @spec child_spec(keyword()) :: Supervisor.child_spec()
    def child_spec(opts) do
      %{
        id: {__MODULE__, Keyword.get(opts, :id, :default)},
        start: {__MODULE__, :start_link, [opts]},
        restart: Keyword.get(opts, :restart, :transient),
        type: :worker
      }
    end

    @doc """
    Starts a host attached to `:channel` as `:endpoint`.

    Options: `:things` maps Thing ids to `Wotex.Runtime.ConsumedThing` values,
    `:capabilities` lists the host's `WotexContinuum.Capability` values,
    `:clock` supplies time, `:node_id` names the host scope, and `:limits` are
    codec limits.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @doc "Returns received, admitted, rejected, dispatched and lifecycle state."
    @spec stats(pid()) :: map()
    def stats(host), do: GenServer.call(host, :stats)

    @doc "Moves the host lifecycle to `draining`; later intents are refused."
    @spec drain(pid()) :: {:ok, Lifecycle.t()} | {:error, WotexContinuum.Error.t()}
    def drain(host), do: GenServer.call(host, :drain)

    @impl GenServer
    def init(opts) do
      channel = Keyword.fetch!(opts, :channel)
      endpoint = Keyword.fetch!(opts, :endpoint)
      clock = Keyword.get(opts, :clock, fn -> DateTime.utc_now() end)
      :ok = Channel.attach(channel, endpoint, self(), source: true)

      {:ok, mode} = Mode.from_map(%{deployment: :saas, connectivity: :connected})

      {:ok, lifecycle} =
        Lifecycle.from_map(%{
          subject_id: endpoint,
          state: :active,
          generation: 0,
          changed_at: clock.()
        })

      {:ok,
       %{
         channel: channel,
         endpoint: endpoint,
         clock: clock,
         node_id: Keyword.get(opts, :node_id, endpoint),
         mode: mode,
         things: Keyword.get(opts, :things, %{}),
         capabilities: Keyword.get(opts, :capabilities, []),
         limits: Keyword.get(opts, :limits, []),
         lifecycle: lifecycle,
         manifests: %{},
         observations: %{},
         received: [],
         rejected: [],
         dispatches: %{},
         results: [],
         result_sequence: 0
       }}
    end

    @impl GenServer
    def handle_call(:stats, _from, state) do
      {:reply,
       %{
         received: Enum.reverse(state.received),
         rejected: Enum.reverse(state.rejected),
         observations: state.observations,
         dispatches: state.dispatches,
         results: Enum.reverse(state.results),
         manifests:
           state.manifests |> Map.keys() |> Enum.map(fn {_source, id} -> id end) |> Enum.sort(),
         manifest_sources:
           state.manifests
           |> Map.keys()
           |> Enum.map(fn {source, id} -> %{source: source, manifest_id: id} end)
           |> Enum.sort_by(&{&1.source, &1.manifest_id}),
         lifecycle: state.lifecycle
       }, state}
    end

    def handle_call(:drain, _from, state) do
      case Lifecycle.transition(state.lifecycle, :draining, state.clock.(), reason: "host drain") do
        {:ok, lifecycle} -> {:reply, {:ok, lifecycle}, %{state | lifecycle: lifecycle}}
        {:error, error} -> {:reply, {:error, error}, state}
      end
    end

    @impl GenServer
    def handle_info(
          {:wotex_continuum, endpoint, source, delivery_id, receipt_token, wire},
          %{endpoint: endpoint} = state
        ) do
      state =
        case Channel.ack(state.channel, delivery_id, receipt_token) do
          :ok ->
            case Codec.decode(wire, state.limits) do
              {:ok, value} ->
                admit(value, delivery_id, source, state)

              {:error, error} ->
                reject(state, delivery_id, source, :undecodable, error.code)
            end

          {:error, _error} ->
            state
        end

      {:noreply, state}
    end

    def handle_info(_message, state), do: {:noreply, state}

    defp admit(%Manifest{} = manifest, delivery_id, source, state) do
      state = record(state, delivery_id, source, "continuum_manifest", manifest.manifest_id)

      schema_version = WotexContinuum.schema_version()

      case Manifest.compatible_with?(manifest, schema_version, state.capabilities) do
        :ok ->
          put_in(state, [:manifests, {source, manifest.manifest_id}], manifest)

        {:error, _mismatches} ->
          reject(state, delivery_id, source, :incompatible_manifest, manifest.manifest_id)
      end
    end

    defp admit(%ObservationProposal{} = proposal, delivery_id, source, state) do
      state = record(state, delivery_id, source, "observation_proposal", proposal.proposal_id)
      key = {proposal.thing_id, proposal.affordance_type, proposal.affordance_name}
      watermark = get_in(state.observations, [key, :sequence])

      cond do
        proposal.context.node_id != source ->
          reject(state, delivery_id, source, :source_mismatch, proposal.proposal_id)

        not Map.has_key?(state.things, proposal.thing_id) ->
          reject(state, delivery_id, source, :unknown_thing, proposal.proposal_id)

        is_nil(proposal.sequence) ->
          reject(state, delivery_id, source, :missing_sequence, proposal.proposal_id)

        is_integer(watermark) and proposal.sequence <= watermark ->
          reject(state, delivery_id, source, :stale_observation, proposal.proposal_id)

        true ->
          observed = %{
            value: proposal.value,
            sequence: proposal.sequence,
            observed_at: proposal.observed_at,
            proposal_id: proposal.proposal_id
          }

          put_in(state, [:observations, key], observed)
      end
    end

    defp admit(%ActionIntent{} = intent, delivery_id, source, state) do
      state = record(state, delivery_id, source, "action_intent", intent.intent_id)
      key = intent.idempotency_key || intent.intent_id

      cond do
        state.lifecycle.state != :ready and state.lifecycle.state != :active ->
          reject(state, delivery_id, source, :host_not_accepting, intent.intent_id)

        intent.context.node_id != source ->
          reject(state, delivery_id, source, :source_mismatch, intent.intent_id)

        not accepted_manifest?(state, source) ->
          reject(state, delivery_id, source, :stale_authority, intent.intent_id)

        Map.has_key?(state.dispatches, key) ->
          state = update_in(state.dispatches[key], &%{&1 | duplicates: &1.duplicates + 1})
          reject(state, delivery_id, source, :duplicate_intent, intent.intent_id)

        not Map.has_key?(state.things, intent.thing_id) ->
          reject(state, delivery_id, source, :unknown_thing, intent.intent_id)

        true ->
          dispatch(state, intent, key, source)
      end
    end

    defp admit(%module{} = value, delivery_id, source, state) do
      state = record(state, delivery_id, source, module.kind(), item_id(value))

      case value do
        %Lifecycle{} -> state
        _other -> state
      end
    end

    defp dispatch(state, intent, key, source) do
      consumed = Map.fetch!(state.things, intent.thing_id)
      context = Context.new!(request_id: "intent:" <> intent.intent_id)
      outcome = ConsumedThing.invoke_action(consumed, intent.action_name, intent.input, context)

      state =
        put_in(state, [:dispatches, key], %{
          intent_id: intent.intent_id,
          duplicates: 0,
          outcome: outcome_tag(outcome)
        })

      reply(state, intent, outcome, source)
    end

    defp reply(state, intent, outcome, source) do
      sequence = state.result_sequence + 1

      {:ok, scope} =
        ExecutionScope.from_map(%{
          execution_id: "host-exec-#{sequence}",
          node_id: state.node_id,
          mode: state.mode,
          observed_at: state.clock.()
        })

      {:ok, result} =
        Wire.result_from_runtime(
          outcome,
          "result-#{sequence}",
          intent.intent_id,
          scope,
          state.clock.()
        )

      {:ok, _delivery} =
        Channel.send_value(state.channel, state.endpoint, source, result)

      %{state | result_sequence: sequence, results: [result | state.results]}
    end

    defp outcome_tag({:ok, result}), do: {:ok, result.status}
    defp outcome_tag({:error, error}), do: {:error, error.code}

    defp accepted_manifest?(state, source) do
      Enum.any?(state.manifests, fn {{manifest_source, _id}, _manifest} ->
        manifest_source == source
      end)
    end

    defp record(state, delivery_id, source, kind, item_id),
      do: %{
        state
        | received: [
            %{delivery_id: delivery_id, source: source, kind: kind, item_id: item_id}
            | state.received
          ]
      }

    defp reject(state, delivery_id, source, reason, item_id),
      do: %{
        state
        | rejected: [
            %{delivery_id: delivery_id, source: source, reason: reason, item_id: item_id}
            | state.rejected
          ]
      }

    defp item_id(%{__struct__: _module} = value) do
      Enum.find_value(
        [
          :result_id,
          :evidence_id,
          :delivery_id,
          :degradation_id,
          :receipt_id,
          :subject_id,
          :execution_id,
          :id
        ],
        "unknown",
        &Map.get(value, &1)
      )
    end
  end
end
