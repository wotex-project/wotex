# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(WotexContinuum.Codec) and Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Continuum.Wire do
    @moduledoc """
    Conversions between in-memory sibling values and continuum wire values.

    These follow the mapping documented by the continuum package: an Nx
    observation becomes an `observation_proposal`, an Nx Action proposal becomes
    an `action_intent`, and a runtime result or error becomes an
    `action_result`. Integer time coordinates are anchored to an explicit epoch
    supplied by the host; units and sources travel in `extensions` under
    absolute lab IRIs. Every conversion is lossy and grants nothing: the host
    still owns identity, ordering, authority and effects.
    """

    alias Wotex.Nx.{ActionProposal, Observation}
    alias Wotex.Runtime.{Error, Result}
    alias WotexContinuum.{ActionIntent, ActionResult, ExecutionScope, ObservationProposal}

    @unit_iri "urn:wotex:lab:continuum:unit"
    @source_iri "urn:wotex:lab:continuum:source"
    @quality_iri "urn:wotex:lab:continuum:quality"
    @operation_iri "urn:wotex:lab:continuum:operation"

    @doc "Converts an Nx observation to a proposal; `epoch` anchors the integer coordinate in milliseconds."
    @spec proposal_from_observation(Observation.t(), ExecutionScope.t(), DateTime.t(), keyword()) ::
            {:ok, ObservationProposal.t()} | {:error, WotexContinuum.Error.t()}
    def proposal_from_observation(
          observation,
          %ExecutionScope{} = scope,
          %DateTime{} = epoch,
          opts \\ []
        ) do
      fields = Observation.to_map(observation)

      extensions =
        %{@quality_iri => Atom.to_string(fields.quality)}
        |> put_extension(@unit_iri, fields.unit)
        |> put_extension(@source_iri, fields.source)

      ObservationProposal.from_map(%{
        proposal_id: fields.id,
        thing_id: fields.thing_id,
        affordance_type: fields.affordance_type,
        affordance_name: fields.affordance_name,
        value: fields.value,
        observed_at: DateTime.add(epoch, fields.observed_at, :millisecond),
        sequence: Keyword.get(opts, :sequence),
        context: scope,
        extensions: extensions
      })
    end

    @doc "Converts an Nx Action proposal to an intent with an explicit idempotency key."
    @spec intent_from_proposal(ActionProposal.t(), ExecutionScope.t(), DateTime.t(), keyword()) ::
            {:ok, ActionIntent.t()} | {:error, WotexContinuum.Error.t()}
    def intent_from_proposal(proposal, %ExecutionScope{} = scope, %DateTime{} = epoch, opts \\ []) do
      fields = ActionProposal.to_map(proposal)

      ActionIntent.from_map(%{
        intent_id: fields.id,
        thing_id: fields.thing_id,
        action_name: fields.action_name,
        input: fields.input,
        requested_at: DateTime.add(epoch, fields.proposed_at, :millisecond),
        idempotency_key: Keyword.get(opts, :idempotency_key, fields.id),
        requested_by: Keyword.get(opts, :requested_by),
        context: scope
      })
    end

    @doc "Converts a runtime outcome for an intent into an action result at `completed_at`."
    @spec result_from_runtime(
            {:ok, Result.t()} | {:error, Error.t()},
            String.t(),
            String.t(),
            ExecutionScope.t(),
            DateTime.t()
          ) :: {:ok, ActionResult.t()} | {:error, WotexContinuum.Error.t()}
    def result_from_runtime(
          outcome,
          result_id,
          intent_id,
          %ExecutionScope{} = scope,
          %DateTime{} = at
        ) do
      base = %{result_id: result_id, intent_id: intent_id, completed_at: at, context: scope}

      case outcome do
        {:ok, %Result{status: :ok, payload: payload, operation: operation}} ->
          ActionResult.from_map(
            Map.merge(base, %{
              status: :succeeded,
              output: payload,
              extensions: %{@operation_iri => Atom.to_string(operation)}
            })
          )

        {:ok, %Result{status: :accepted, operation: operation}} ->
          ActionResult.from_map(
            Map.merge(base, %{
              status: :accepted,
              extensions: %{@operation_iri => Atom.to_string(operation)}
            })
            |> Map.delete(:completed_at)
          )

        {:error, %Error{code: code, phase: phase}} ->
          ActionResult.from_map(
            Map.merge(base, %{
              status: :failed,
              error: %{
                code: Atom.to_string(code),
                message: "runtime rejected the intent",
                details: %{"phase" => Atom.to_string(phase)}
              }
            })
          )
      end
    end

    defp put_extension(extensions, _, nil), do: extensions
    defp put_extension(extensions, iri, value), do: Map.put(extensions, iri, value)
  end
end
