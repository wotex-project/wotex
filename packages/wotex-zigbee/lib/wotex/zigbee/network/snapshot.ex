defmodule Wotex.Zigbee.Network.Snapshot do
  @moduledoc """
  Separate bounded device and network readings from one coordinator owner epoch.

  `:observed` means both exact replies were obtained in order within the
  workflow deadline. `:partial` retains available readings and a bounded
  issue. `:matching` consistency compares reported short address and device
  state only; `:changed` preserves their disagreement. A pair of sequential
  readings is not an atomic network image, credential/counter continuity or
  proof that the coordinator is authenticated, commissioned or reachable.

  Every reading preserves its complete payload and owner observation time.
  Unknown capability/state bits, uninitialized addresses and associated-route
  duplicates remain visible. Host epoch/time fencing supplies observation
  context rather than radio authentication. No status is invented for the
  network-info reply, which has none in the exact SDK layout.
  """

  alias Wotex.Zigbee.{Error, Network}

  @enforce_keys [:owner_epoch, :outcome, :consistency, :readings, :issue]
  defstruct @enforce_keys

  @type input_reading :: %{
          phase: Network.phase(),
          payload: binary(),
          observed_at_ms: integer()
        }
  @type reading :: %{
          phase: Network.phase(),
          payload: binary(),
          observed_at_ms: integer(),
          value: Network.device_info() | Network.network_info()
        }
  @type t :: %__MODULE__{
          owner_epoch: reference(),
          outcome: :observed | :partial,
          consistency: :matching | :changed | :unavailable,
          readings: [reading()],
          issue: Error.kind() | nil
        }

  @issues [
    :timeout,
    :coordinator_lost,
    :serial,
    :invalid_frame,
    :overload,
    :status_failure,
    :correlation_exhausted
  ]
  @max_time 0x7FFFFFFFFFFFFFFF

  @doc """
  Builds evidence from zero to two ordered raw readings and one bounded issue.

  Each input map has exactly `phase`, `payload` and `observed_at_ms`. The
  device reading precedes the network reading; observation time never rewinds.
  Values are decoded from raw bytes rather than accepted as caller claims.
  Missing readings and failed device status require an explicit issue. Changed
  route/state remains a completed observation with changed consistency. These
  consistency checks do not prove that an owner ran.
  """
  @spec new(reference(), [input_reading()], Error.kind() | nil) ::
          {:ok, t()} | {:error, Error.t()}
  def new(epoch, inputs, issue \\ nil) do
    with true <- is_reference(epoch) and bounded_readings?(inputs),
         true <- issue == nil or issue in @issues,
         {:ok, readings} <- decode_readings(inputs),
         true <- complete?(readings) or issue != nil do
      consistency = consistency(readings)
      outcome = if issue == nil, do: :observed, else: :partial

      {:ok,
       %__MODULE__{
         owner_epoch: epoch,
         outcome: outcome,
         consistency: consistency,
         readings: readings,
         issue: issue
       }}
    else
      _ -> failure()
    end
  end

  @doc "Revalidates the complete snapshot and every retained decoded value after copying."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = snapshot) do
    if map_size(snapshot) == 6 and
         Enum.all?(@enforce_keys, &Map.has_key?(snapshot, &1)) and
         bounded_readings?(snapshot.readings) and
         Enum.all?(snapshot.readings, &reading_shape?/1) do
      inputs = Enum.map(snapshot.readings, &Map.delete(&1, :value))

      case new(snapshot.owner_epoch, inputs, snapshot.issue) do
        {:ok, rebuilt} -> rebuilt == snapshot
        _ -> false
      end
    else
      false
    end
  end

  def valid?(_), do: false

  defp decode_readings(inputs) do
    result =
      Enum.reduce_while(Enum.with_index(inputs), {:ok, []}, fn {input, index}, {:ok, previous} ->
        phase = if index == 0, do: :device_info, else: :network_info

        with true <-
               is_map(input) and map_size(input) == 3 and
                 Enum.all?([:phase, :payload, :observed_at_ms], &Map.has_key?(input, &1)),
             true <- input.phase == phase and valid_time?(input.observed_at_ms),
             true <- previous == [] or hd(previous).observed_at_ms <= input.observed_at_ms,
             {:ok, value} <- decode(phase, input.payload) do
          {:cont, {:ok, [Map.put(input, :value, value) | previous]}}
        else
          _ -> {:halt, failure()}
        end
      end)

    case result do
      {:ok, readings} -> {:ok, Enum.reverse(readings)}
      error -> error
    end
  end

  defp decode(:device_info, payload), do: Network.device_info(payload)
  defp decode(:network_info, payload), do: Network.network_info(payload)
  defp complete?([%{value: %{status: 0}}, %{phase: :network_info}]), do: true
  defp complete?(_), do: false

  defp bounded_readings?([]), do: true
  defp bounded_readings?([_]), do: true
  defp bounded_readings?([_, _]), do: true
  defp bounded_readings?(_), do: false

  defp consistency([%{value: %{status: 0} = device}, %{value: network}]) do
    if device.network_address == network.network_address and
         device.device_state == network.device_state,
       do: :matching,
       else: :changed
  end

  defp consistency(_), do: :unavailable

  defp reading_shape?(value),
    do:
      is_map(value) and map_size(value) == 4 and
        Enum.all?([:phase, :payload, :observed_at_ms, :value], &Map.has_key?(value, &1))

  defp valid_time?(time), do: is_integer(time) and time >= -@max_time - 1 and time <= @max_time
  defp failure, do: {:error, %Error{kind: :invalid_value, operation: :network}}
end
