defmodule Wotex.Zigbee.Config do
  @moduledoc """
  Pure, explicit admission for one TI ZNP serial coordinator.

  The consumer supplies a serial adapter, stable hardware identity and the
  exact five-byte `SYS_VERSION` tuple expected from its firmware. The selected
  host API is TI CC26x2 SDK 2.30.00.34 with Monitor/Test revision 1.14,
  115200 baud and 8-N-1. The adapter decides how its host configures 8-N-1
  and optional RTS/CTS. No serial path is discovered automatically.

  Default bounds admit 4,096 buffered serial bytes, 128 queued indications
  and a 5,000 ms command deadline. Only one synchronous ZNP request is
  outstanding because SRSP frames carry no independent correlation token.
  """

  alias Wotex.Zigbee.Error

  @enforce_keys [:serial, :device_id, :expected_version]
  defstruct serial: nil,
            device_id: nil,
            expected_version: nil,
            serial_options: [],
            flow_control: :none,
            max_buffer_bytes: 4_096,
            max_events: 128,
            timeout_ms: 5_000

  @type t :: %__MODULE__{
          serial: module(),
          device_id: binary(),
          expected_version: {byte(), byte(), byte(), byte(), byte()},
          serial_options: keyword(),
          flow_control: :none | :rts_cts,
          max_buffer_bytes: 5..65_536,
          max_events: 1..1_024,
          timeout_ms: 1..60_000
        }

  @doc "Builds an inert coordinator configuration and rejects unknown options."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    allowed =
      ~w(serial device_id expected_version serial_options flow_control max_buffer_bytes max_events timeout_ms)a

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) do
      config = struct(__MODULE__, options)
      if valid?(config), do: {:ok, config}, else: invalid()
    else
      invalid()
    end
  end

  def new(_), do: invalid()

  @doc "Checks all fields of a configuration, including a copied or modified one."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = config) do
    is_atom(config.serial) and config.serial != nil and
      is_binary(config.device_id) and byte_size(config.device_id) in 1..128 and
      valid_version?(config.expected_version) and
      Keyword.keyword?(config.serial_options) and
      Enum.all?(
        Keyword.keys(config.serial_options),
        &(&1 not in [:baud_rate, :data_bits, :stop_bits, :parity, :flow_control])
      ) and
      length(config.serial_options) == length(Enum.uniq(Keyword.keys(config.serial_options))) and
      config.flow_control in [:none, :rts_cts] and
      in_range?(config.max_buffer_bytes, 5, 65_536) and
      in_range?(config.max_events, 1, 1_024) and
      in_range?(config.timeout_ms, 1, 60_000)
  end

  defp valid_version?(value) when is_tuple(value) and tuple_size(value) == 5 do
    value
    |> Tuple.to_list()
    |> Enum.all?(&in_range?(&1, 0, 255))
  end

  defp valid_version?(_), do: false

  defp in_range?(value, minimum, maximum),
    do: is_integer(value) and value >= minimum and value <= maximum

  defp invalid, do: {:error, %Error{kind: :invalid_config, operation: :config}}
end
