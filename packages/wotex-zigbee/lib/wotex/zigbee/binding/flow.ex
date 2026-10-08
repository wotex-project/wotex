defmodule Wotex.Zigbee.Binding.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{Binding, Event, Reply}
  alias Wotex.Zigbee.Binding.Result

  @type t :: %{
          request: Binding.t(),
          epoch: reference(),
          admission: Reply.t() | nil,
          response: Event.t() | nil
        }

  @doc false
  @spec new(Binding.t(), reference()) :: t()
  def new(request, epoch), do: %{request: request, epoch: epoch, admission: nil, response: nil}

  @doc false
  @spec admit(t(), Reply.t()) :: t()
  def admit(flow, reply), do: %{flow | admission: reply}

  @doc false
  @spec offer(t(), Event.t()) :: {:matched, t()} | :unmatched
  def offer(
        %{response: nil, request: request, epoch: epoch} = flow,
        %Event{
          kind: kind,
          owner_epoch: epoch,
          source_address: route,
          zdo: %{operation: operation}
        } = event
      )
      when kind in [:zdo_bind, :zdo_unbind] and route == request.route_address and
             operation == request.operation,
      do: {:matched, %{flow | response: event}}

  def offer(_, _), do: :unmatched

  @doc false
  @spec advance(t()) :: :waiting | {:done, Result.t()}
  def advance(%{admission: nil}), do: :waiting

  def advance(%{admission: %{status: status}} = flow) when status != 0,
    do: {:done, finish(flow, :ncp_rejected)}

  def advance(%{response: nil}), do: :waiting

  def advance(flow) do
    outcome = if flow.response.status == 0, do: :peer_reported_success, else: :peer_reported_failure
    {:done, result(flow, outcome, nil)}
  end

  @doc false
  @spec finish(t(), atom()) :: Result.t()
  def finish(flow, issue), do: result(flow, :unconfirmed, issue)

  defp result(flow, outcome, issue),
    do: %Result{
      request: flow.request,
      owner_epoch: flow.epoch,
      admission: flow.admission,
      response: flow.response,
      outcome: outcome,
      issue: issue
    }
end
