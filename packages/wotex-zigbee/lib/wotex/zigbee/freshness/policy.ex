defmodule Wotex.Zigbee.Freshness.Policy do
  @moduledoc """
  Explicit consumer expectations for one attribute report or Poll Control Check-in.

  A policy selects a raw IEEE peer and remote/local AF endpoints. Report
  policies also select cluster, attribute, type, ZCL direction and optional
  manufacturer code. These are consumer-adopted semantics, not device
  authentication or permission to configure reporting.

  `expected_interval_ms` is an integer from 1 ms to 365 days, or an explicit
  `:disabled` expectation. Reports also admit `:on_change`, which has no
  periodic deadline. `grace_ms` is 0 through 365 days, and must be zero for
  nonperiodic expectations. No interval is inferred from a device label, a
  successful configuration response or an observed Check-in.
  """

  alias Wotex.Zigbee.Error
  alias Wotex.Zigbee.ZCL.Value

  @max_interval_ms 31_536_000_000
  @common [:peer_ieee, :remote_endpoint, :local_endpoint, :expected_interval_ms, :grace_ms]
  @report [:cluster, :attribute_id, :type, :direction, :manufacturer, :full_range]
  @fields [:kind | @common ++ @report]

  @enforce_keys @fields
  defstruct @fields

  @type key ::
          {:report | :checkin, binary(), pos_integer(), pos_integer(), non_neg_integer(),
           non_neg_integer() | nil, Wotex.Zigbee.ZCL.direction(), non_neg_integer() | nil}
  @opaque t :: %__MODULE__{
            kind: :report | :checkin,
            peer_ieee: <<_::64>>,
            remote_endpoint: 1..240,
            local_endpoint: 1..240,
            cluster: 0..0xFFFF,
            attribute_id: non_neg_integer() | nil,
            type: byte() | nil,
            direction: Wotex.Zigbee.ZCL.direction(),
            manufacturer: non_neg_integer() | nil,
            full_range: boolean(),
            expected_interval_ms: pos_integer() | :on_change | :disabled,
            grace_ms: non_neg_integer()
          }

  @doc """
  Builds a finite report expectation with an explicit type and cadence.

  Required options are `peer_ieee`, `remote_endpoint`, `local_endpoint`,
  `cluster`, `attribute_id`, `type` and `expected_interval_ms`. Defaults are
  `grace_ms: 0`, `direction: :server_to_client`, `manufacturer: nil` and
  `full_range: false`. Only the finite `Wotex.Zigbee.ZCL.Value` types are
  admitted. Numeric full-range policy requires an adopted attribute definition.
  Unknown or duplicate options fail without coercion.
  """
  @spec report(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def report(options), do: build(:report, options, @common ++ @report)

  @doc """
  Builds a Check-in expectation for cluster `0x0020`, server to client.

  Required options are `peer_ieee`, `remote_endpoint`, `local_endpoint` and
  `expected_interval_ms`; grace defaults to zero. The interval is periodic
  or explicitly `:disabled`. Convert a qualified quartersecond interval with
  `Wotex.Zigbee.ZCL.PollControl.quarterseconds_to_ms/1` separately. Wire zero
  CheckInInterval means disabled; this constructor requires that explicit
  disposition rather than accepting a zero periodic interval.
  """
  @spec checkin(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def checkin(options), do: build(:checkin, options, @common)

  @doc "Revalidates complete selectors, cadence, types and numeric policy after copying."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = policy) do
    map_size(policy) == length(@fields) + 1 and
      Enum.all?(@fields, &Map.has_key?(policy, &1)) and
      valid_ieee?(policy.peer_ieee) and endpoint?(policy.remote_endpoint) and
      endpoint?(policy.local_endpoint) and cadence?(policy) and selector?(policy)
  end

  def valid?(_), do: false

  @doc """
  Returns the stable stream selector, or nil for an invalid policy.

  Type, full-range interpretation and cadence are excluded: explicitly arming
  an updated policy replaces that selector's expectation and starts a new
  window. Different attributes, headers, endpoints and peers remain separate.
  """
  @spec key(t()) :: key() | nil
  def key(policy) do
    if valid?(policy),
      do:
        {policy.kind, policy.peer_ieee, policy.remote_endpoint, policy.local_endpoint,
         policy.cluster, policy.attribute_id, policy.direction, policy.manufacturer},
      else: nil
  end

  defp build(kind, options, allowed) when is_list(options) do
    if Keyword.keyword?(options) and length(options) <= length(allowed) and
         Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         length(options) == length(Enum.uniq(Keyword.keys(options))) do
      fields = Map.new(@fields, &{&1, nil})

      defaults = %{
        kind: kind,
        cluster: if(kind == :checkin, do: 0x0020, else: nil),
        direction: :server_to_client,
        grace_ms: 0,
        full_range: false
      }

      fields =
        fields
        |> Map.merge(defaults)
        |> Map.merge(Map.new(options))

      policy = struct!(__MODULE__, fields)
      if valid?(policy), do: {:ok, policy}, else: failure()
    else
      failure()
    end
  end

  defp build(_, _, _), do: failure()

  defp cadence?(policy) do
    interval = policy.expected_interval_ms

    in_range?(policy.grace_ms, 0, @max_interval_ms) and
      (in_range?(interval, 1, @max_interval_ms) or
         (interval == :disabled and policy.grace_ms == 0) or
         (interval == :on_change and policy.kind == :report and policy.grace_ms == 0))
  end

  defp selector?(%{kind: :checkin} = policy),
    do:
      policy.cluster == 0x0020 and policy.attribute_id == nil and policy.type == nil and
        policy.direction == :server_to_client and policy.manufacturer == nil and
        policy.full_range == false

  defp selector?(%{kind: :report} = policy) do
    in_range?(policy.cluster, 0, 0xFFFF) and in_range?(policy.attribute_id, 0, 0xFFFF) and
      policy.direction in [:server_to_client, :client_to_server] and
      (policy.manufacturer == nil or in_range?(policy.manufacturer, 0, 0xFFFF)) and
      is_boolean(policy.full_range) and type_policy?(policy.type, policy.full_range)
  end

  defp selector?(_), do: false

  defp type_policy?(type, full) do
    case Value.category(type) do
      {:ok, :analog} -> true
      {:ok, :discrete} -> not full
      _ -> false
    end
  end

  defp valid_ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp valid_ieee?(_), do: false
  defp endpoint?(value), do: in_range?(value, 1, 240)
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure, do: {:error, %Error{kind: :invalid_value, operation: :freshness_policy}}
end
