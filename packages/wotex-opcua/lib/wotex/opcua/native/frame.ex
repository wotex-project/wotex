defmodule Wotex.OPCUA.Native.Frame do
  @moduledoc """
  Encodes the bounded outer native request and maps the ready clock sample.

  This pure boundary does not validate operation parameters or activate an OPC
  UA Session. The owner supplies its own monotonic deadline and current sample;
  the translated native deadline never extends the original owner budget.
  """

  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Ready

  @maximum_generation 18_446_744_073_709_551_615
  @maximum_clock 9_223_372_036_854_775_807
  @maximum_frame 131_072
  @operations ~w(open read health write call browse browse_next browse_release subscribe unsubscribe cancel close)
  @limits [
    max_bytes: 131_071,
    max_depth: 8,
    max_nodes: 4096,
    max_collection_size: 1024,
    max_string_bytes: 65_536
  ]

  @typedoc "An owner deadline mapped onto the same-host native monotonic clock."
  @type admission :: %{deadline_ms: non_neg_integer(), timeout_ms: pos_integer()}

  @doc "Maps readiness and the current owner budget without restarting the deadline."
  @spec admission(Ready.t(), integer(), integer(), integer(), integer()) ::
          {:ok, admission()} | {:error, Error.t()}
  def admission(%Ready{clock_ms: native}, received, deadline, now, timeout)
      when is_integer(received) and is_integer(deadline) and is_integer(now) and
             is_integer(timeout) and timeout in 1..60_000 and native in 0..@maximum_clock do
    translated = native + deadline - received

    cond do
      now < received or deadline <= received or now >= deadline ->
        {:error, Error.new(:deadline_exceeded, :deadline)}

      translated < 0 or translated > @maximum_clock ->
        {:error, Error.new(:invalid_native_frame, :deadline)}

      true ->
        {:ok, %{deadline_ms: translated, timeout_ms: min(timeout, deadline - now)}}
    end
  end

  def admission(_, _, _, _, _), do: {:error, Error.new(:invalid_native_frame, :deadline)}

  @doc "Encodes one closed version-1 request line for the native process."
  @spec request(term(), term(), term(), term(), term(), term()) ::
          {:ok, binary()} | {:error, Error.t()}
  def request(generation, id, operation, parameters, timeout_ms, deadline_ms)
      when is_map(parameters) do
    envelope = %{
      "version" => 1,
      "generation" => generation,
      "id" => id,
      "operation" => operation,
      "parameters" => parameters,
      "timeout_ms" => timeout_ms,
      "deadline_ms" => deadline_ms
    }

    with true <- valid_identity?(generation, id, operation),
         true <- valid_budget?(timeout_ms, deadline_ms),
         {:ok, bytes} <- Wotex.JSON.encode(envelope, @limits),
         true <- byte_size(bytes) + 1 <= @maximum_frame do
      {:ok, bytes <> "\n"}
    else
      _ -> {:error, Error.new(:invalid_native_frame, :request)}
    end
  end

  def request(_, _, _, _, _, _), do: {:error, Error.new(:invalid_native_frame, :request)}

  defp valid_identity?(generation, id, operation)
       when is_integer(generation) and generation in 1..@maximum_generation and
              is_binary(id) and byte_size(id) in 1..64 and
              is_binary(operation) and operation in @operations,
       do: printable_ascii?(id)

  defp valid_identity?(_, _, _), do: false

  defp valid_budget?(timeout, deadline)
       when is_integer(timeout) and timeout in 1..60_000 and
              is_integer(deadline) and deadline in 0..@maximum_clock,
       do: true

  defp valid_budget?(_, _), do: false

  defp printable_ascii?(id), do: Enum.all?(:binary.bin_to_list(id), &(&1 in 0x20..0x7E))
end
