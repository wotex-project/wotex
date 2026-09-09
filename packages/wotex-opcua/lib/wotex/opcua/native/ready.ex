defmodule Wotex.OPCUA.Native.Ready do
  @moduledoc """
  Validates the native SDK's process-readiness control frame.

  `decode/1` accepts one LF-terminated JSON object of at most 4096 bytes. The
  version, backend and reviewed SDK revision must match exactly; `clock_ms` is
  an unsigned monotonic sample bounded by signed 64-bit range. Duplicate keys,
  extra fields, fractional clocks and extra lines are rejected before a ready
  value reaches the owner. This value establishes process readiness only; it
  does not establish an authenticated OPC UA Session or an accepted service.

  The decoder is pure. The process owner captures its own receive time separately
  and uses that sample with `clock_ms` when constructing native deadlines.

  ## Examples

      iex> Wotex.OPCUA.Native.Ready.decode("not JSON\\n")
      {:error, %Wotex.OPCUA.Error{code: :invalid_native_ready, field: :ready}}
  """

  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Source

  @revision (case Source.fetch(:open62541) do
               {:ok, source} -> source.commit
             end)
  @keys ~w(backend clock_ms event revision version)
  @maximum_clock 9_223_372_036_854_775_807

  @enforce_keys [:clock_ms]
  defstruct [:clock_ms]

  @typedoc "A validated native process clock; no Session or protocol capability is implied."
  @type t :: %__MODULE__{clock_ms: non_neg_integer()}

  @doc "Decodes one complete bootstrap line, rejecting every unsupported frame shape."
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(frame) when is_binary(frame) and byte_size(frame) in 1..4096 do
    with {offset, 1} when offset == byte_size(frame) - 1 <- :binary.match(frame, "\n"),
         {:ok, value} <-
           Wotex.JSON.decode(binary_part(frame, 0, offset),
             max_bytes: 4095,
             max_depth: 1,
             max_nodes: 6,
             max_string_bytes: 64,
             max_collection_size: 5
           ),
         %{
           "version" => 1,
           "event" => "ready",
           "backend" => "open62541",
           "revision" => @revision,
           "clock_ms" => clock
         }
         when is_integer(clock) and clock >= 0 and clock <= @maximum_clock <- value,
         true <- Enum.sort(Map.keys(value)) == @keys do
      {:ok, %__MODULE__{clock_ms: clock}}
    else
      _ -> invalid()
    end
  end

  def decode(_), do: invalid()

  defp invalid, do: {:error, Error.new(:invalid_native_ready, :ready)}
end
