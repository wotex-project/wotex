defmodule Wotex.OPCUA.Native.Frame do
  @moduledoc """
  Encodes the bounded outer native request and maps the ready clock sample.

  This pure boundary does not validate operation parameters or activate an OPC
  UA Session. The owner supplies its own monotonic deadline and current sample;
  the translated native deadline never extends the original owner budget.
  """

  alias Wotex.OPCUA.{Binary, Error}
  alias Wotex.OPCUA.Native.Ready

  @maximum_generation 18_446_744_073_709_551_615
  @maximum_clock 9_223_372_036_854_775_807
  @maximum_frame 131_072
  @operations ~w(open read health write call browse browse_next browse_release subscribe unsubscribe cancel close)
  @codes ~w(invalid_request invalid_value invalid_response unsupported_type unsupported_protocol backend_mismatch busy deadline_exceeded authentication_failed certificate_invalid connection_failed remote_error response_mismatch response_limit sequence_gap subscription_lost receiver_overflow cleanup_failed canceled)a
  @phases ~w(validation opening admission exchange decode cleanup)a
  @effects ~w(none unknown)a
  @terminal_keys ~w(error event generation version)
  @response_keys ~w(generation id ok result version)
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

  @doc "Encodes an initial or bounded replenishment credit control."
  @spec credit(term(), term(), term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def credit(generation, sequence, messages, bytes)
      when is_integer(generation) and generation in 1..@maximum_generation and
             is_integer(sequence) and sequence in 1..@maximum_generation and
             is_integer(messages) and messages in 1..16 and
             is_integer(bytes) and bytes in 1..262_144 do
    control = %{
      "version" => 1,
      "generation" => generation,
      "event" => "credit",
      "sequence" => sequence,
      "messages" => messages,
      "bytes" => bytes
    }

    case Wotex.JSON.encode(control, max_bytes: 4095, max_depth: 1, max_nodes: 7) do
      {:ok, encoded} when byte_size(encoded) < 4096 -> {:ok, encoded <> "\n"}
      _ -> {:error, Error.new(:invalid_native_frame, :credit)}
    end
  end

  def credit(_, _, _, _), do: {:error, Error.new(:invalid_native_frame, :credit)}

  @doc "Decodes one terminal control for the expected generation without exposing native text."
  @spec terminal(term(), term()) :: {:ok, Error.t()} | {:error, Error.t()}
  def terminal(frame, generation)
      when is_binary(frame) and byte_size(frame) in 1..4096 and
             is_integer(generation) and generation in 1..@maximum_generation do
    size = byte_size(frame)

    with {offset, 1} when offset == size - 1 <- :binary.match(frame, "\n"),
         {:ok, decoded} <-
           Wotex.JSON.decode(binary_part(frame, 0, offset),
             max_bytes: 4095,
             max_depth: 2,
             max_nodes: 12,
             max_collection_size: 5,
             max_string_bytes: 128
           ),
         %{"version" => 1, "generation" => ^generation, "event" => "terminal", "error" => error} <-
           decoded,
         true <- Enum.sort(Map.keys(decoded)) == @terminal_keys,
         {:ok, result} <- terminal_error(error) do
      {:ok, result}
    else
      _ -> {:error, Error.new(:invalid_native_frame, :terminal)}
    end
  end

  def terminal(_, _), do: {:error, Error.new(:invalid_native_frame, :terminal)}

  @doc "Decodes a correlated native service response and validates the open metadata."
  @spec response(term(), term(), term(), term(), term()) ::
          {:ok, term()} | {:native_error, Error.t()} | {:error, Error.t()}
  def response(frame, generation, id, operation, requested_timeout)
      when is_binary(frame) and byte_size(frame) in 1..@maximum_frame and
             is_integer(generation) and generation in 1..@maximum_generation and
             is_binary(id) and is_binary(operation) do
    size = byte_size(frame)

    with {offset, 1} when offset == size - 1 <- :binary.match(frame, "\n"),
         {:ok, decoded} <-
           Wotex.JSON.decode(binary_part(frame, 0, offset),
             max_bytes: @maximum_frame - 1,
             max_depth: 8,
             max_nodes: 4096,
             max_collection_size: 1024,
             max_string_bytes: 65_536
           ),
         %{"version" => 1, "generation" => ^generation, "id" => ^id, "ok" => ok} <-
           decoded do
      case {ok, Enum.sort(Map.keys(decoded))} do
        {true, @response_keys} ->
          response_result(operation, decoded["result"], requested_timeout, generation)

        {false, ["error", "generation", "id", "ok", "version"]} ->
          case terminal_error(decoded["error"]) do
            {:ok, error} -> {:native_error, error}
            _ -> {:error, Error.new(:invalid_native_frame, :response)}
          end

        _ ->
          {:error, Error.new(:invalid_native_frame, :response)}
      end
    else
      _ -> {:error, Error.new(:invalid_native_frame, :response)}
    end
  end

  def response(_, _, _, _, _), do: {:error, Error.new(:invalid_native_frame, :response)}

  defp response_result("close", nil, _, _), do: {:ok, nil}

  defp response_result("write", %{"status" => status} = result, _, _)
       when map_size(result) == 1 and is_integer(status) and
              status in 0..4_294_967_295 do
    if Bitwise.band(status, 0x80000000) == 0,
      do: {:ok, result},
      else: {:error, Error.new(:invalid_native_frame, :response)}
  end

  defp response_result("read", result, _, _) when is_map(result) do
    with {:ok, value} <- native_data_value(result),
         {:ok, _} <- Binary.encode_data_value(value),
         true <- Bitwise.band(value.status, 0x80000000) == 0 do
      {:ok, result}
    else
      _ -> {:error, Error.new(:invalid_native_frame, :response)}
    end
  end

  defp response_result("open", result, requested, expected_generation)
       when is_map(result) and is_integer(requested) and requested in 1000..3_600_000 do
    with %{
           "session_timeout_ms" => timeout,
           "namespace_array" => namespaces,
           "session_generation" => generation
         } <- result,
         true <-
           Enum.sort(Map.keys(result)) ==
             ~w(namespace_array session_generation session_timeout_ms),
         true <- is_number(timeout) and timeout > 0 and timeout <= requested,
         true <- generation == expected_generation,
         true <- namespace_array?(namespaces) do
      {:ok, result}
    else
      _ -> {:error, Error.new(:invalid_native_frame, :response)}
    end
  end

  defp response_result(_, _, _, _), do: {:error, Error.new(:invalid_native_frame, :response)}

  @data_fields %{
    "has_value" => :has_value,
    "value" => :value,
    "status" => :status,
    "source_timestamp" => :source_timestamp,
    "server_timestamp" => :server_timestamp,
    "source_picoseconds" => :source_picoseconds,
    "server_picoseconds" => :server_picoseconds
  }

  defp native_data_value(%{"has_value" => present, "status" => status} = result)
       when is_boolean(present) and is_integer(status) and status in 0..4_294_967_295 and
              map_size(result) <= 7 do
    with true <- Enum.all?(Map.keys(result), &Map.has_key?(@data_fields, &1)),
         true <- Map.has_key?(result, "value") == present,
         {:ok, variant} <- native_variant(result["value"], present) do
      value = Map.new(result, fn {key, field} -> {Map.fetch!(@data_fields, key), field} end)
      {:ok, if(present, do: %{value | value: variant}, else: value)}
    else
      _ -> :error
    end
  end

  defp native_data_value(_), do: :error

  defp native_variant(_, false), do: {:ok, nil}

  defp native_variant(%{"type" => type, "array" => array, "value" => payload} = value, true)
       when is_binary(type) and is_boolean(array) and map_size(value) in [3, 4] do
    with true <- Enum.all?(Map.keys(value), &(&1 in ~w(type array value dimensions))),
         {:ok, payload} <- native_payload(type, array, payload) do
      variant = %{type: type, array: array, value: payload}

      {:ok,
       if(Map.has_key?(value, "dimensions"),
         do: Map.put(variant, :dimensions, value["dimensions"]),
         else: variant
       )}
    else
      _ -> :error
    end
  end

  defp native_variant(_, true), do: :error

  defp native_payload("ByteString", true, values) when is_list(values) do
    values
    |> native_list("ByteString")
  end

  defp native_payload("LocalizedText", true, values) when is_list(values),
    do: native_list(values, "LocalizedText")

  defp native_payload("LocalizedText", false, %{"locale" => locale, "text" => text} = value)
       when map_size(value) == 2,
       do: {:ok, %{locale: locale, text: text}}

  defp native_payload("LocalizedText", false, _), do: :error

  defp native_payload("ByteString", false, nil), do: {:ok, nil}

  defp native_payload("ByteString", false, %{"type" => "bytes", "base64" => base64} = value)
       when map_size(value) == 2 and is_binary(base64),
       do: Base.decode64(base64)

  defp native_payload("ByteString", false, _), do: :error
  defp native_payload(_, _, payload), do: {:ok, payload}

  defp native_list(values, type) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, items} ->
        case native_payload(type, false, value) do
          {:ok, decoded} -> {:cont, {:ok, [decoded | items]}}
          _ -> {:halt, :error}
        end
      end)

    case result do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp namespace_array?(["http://opcfoundation.org/UA/" | _] = entries)
       when length(entries) in 2..1024 do
    Enum.all?(entries, &(is_binary(&1) and byte_size(&1) in 1..4096)) and
      Enum.reduce(entries, 0, &(byte_size(&1) + &2)) <= 131_072 and
      length(Enum.uniq(entries)) == length(entries)
  end

  defp namespace_array?(_), do: false

  defp terminal_error(%{"code" => code, "phase" => phase, "effect" => effect} = error)
       when is_binary(code) and is_binary(phase) and is_binary(effect) do
    with true <- Enum.sort(Map.keys(error)) in [~w(code effect phase), ~w(code effect phase status)],
         {:ok, code_atom} <- finite(code, @codes),
         {:ok, phase_atom} <- finite(phase, @phases),
         {:ok, effect_atom} <- finite(effect, @effects),
         {:ok, details} <- status_details(error, phase_atom) do
      {:ok, %{Error.new(code_atom, nil, details) | effect: effect_atom}}
    else
      _ -> :error
    end
  end

  defp terminal_error(_), do: :error

  defp status_details(error, phase) do
    case Map.fetch(error, "status") do
      :error ->
        {:ok, %{phase: phase}}

      {:ok, status} when is_integer(status) and status in 0..4_294_967_295 ->
        {:ok, %{phase: phase, status: status}}

      _ ->
        :error
    end
  end

  defp finite(value, allowed) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

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
