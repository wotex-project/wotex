defmodule Wotex.Zigbee.Network.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{Error, Frame, Network}
  alias Wotex.Zigbee.Network.Snapshot

  @type t :: %{
          epoch: reference(),
          phase: Network.phase() | :done,
          readings: [Snapshot.input_reading()],
          issue: Error.kind() | nil
        }

  @doc false
  @spec new(reference()) :: t()
  def new(epoch), do: %{epoch: epoch, phase: :device_info, readings: [], issue: nil}

  @doc false
  @spec command(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def command(flow), do: Network.frame(flow.phase)

  @doc false
  @spec admit(t(), binary(), integer()) :: {:ok, t()} | {:error, Error.t()}
  def admit(%{phase: :device_info} = flow, payload, time) do
    with {:ok, device} <- Network.device_info(payload) do
      next = if device.status == 0, do: :network_info, else: :done
      issue = if device.status == 0, do: nil, else: :status_failure
      {:ok, %{append(flow, payload, time) | phase: next, issue: issue}}
    end
  end

  def admit(%{phase: :network_info} = flow, payload, time) do
    with {:ok, _} <- Network.network_info(payload) do
      {:ok, %{append(flow, payload, time) | phase: :done}}
    end
  end

  @doc false
  @spec advance(t()) :: {:next, t()} | {:done, Snapshot.t()}
  def advance(%{phase: :done} = flow), do: {:done, finish(flow, flow.issue)}
  def advance(flow), do: {:next, flow}

  @doc false
  @spec finish(t(), Error.kind() | nil) :: Snapshot.t()
  def finish(flow, issue) do
    {:ok, snapshot} = Snapshot.new(flow.epoch, Enum.reverse(flow.readings), issue)
    snapshot
  end

  defp append(flow, payload, time),
    do: %{
      flow
      | readings: [%{phase: flow.phase, payload: payload, observed_at_ms: time} | flow.readings]
    }
end
