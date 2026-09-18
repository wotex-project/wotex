defmodule Wotex.CoAP.Native.Command do
  @moduledoc """
  Encodes bounded commands for one native OSCORE generation.

  Successful commands receive monotonically increasing decimal identities that
  are never reused. Parameters are validated before identity allocation and are
  projected to the helper's exact JSON command objects. Optional wire fields are omitted
  when absent. The returned line contains one trailing LF and is ready for an
  already owned Port.

  The state retains no credential, body, command line or outstanding-call data.
  Process ownership, deadlines, queue admission and response correlation belong
  to the native session owner.
  """

  alias Wotex.CoAP.Security

  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @maximum_line_bytes 131_072
  @operations [
    :open,
    :body_begin,
    :body_chunk,
    :body_end,
    :request,
    :observe,
    :credit,
    :cancel,
    :close
  ]
  @methods %{get: "GET", post: "POST", put: "PUT", delete: "DELETE"}

  @derive {Inspect, only: [:generation, :next_id]}
  @enforce_keys [:generation]
  defstruct generation: nil, next_id: 1

  @opaque t :: %__MODULE__{generation: pos_integer(), next_id: pos_integer() | :exhausted}

  @doc "Creates an empty command identity space for one nonzero generation."
  @spec new(term()) :: {:ok, t()} | :error
  def new(generation) when is_integer(generation) and generation in 1..@maximum_counter,
    do: {:ok, %__MODULE__{generation: generation}}

  def new(_), do: :error

  @doc "Validates, identifies and encodes one exact native command line."
  @spec encode(t(), term(), term(), term()) ::
          {:ok, String.t(), binary(), t()} | :error | :exhausted
  def encode(
        %__MODULE__{next_id: next_id} = state,
        operation,
        parameters,
        timeout_ms
      )
      when is_integer(next_id) and next_id in 1..@maximum_counter and
             operation in @operations and is_integer(timeout_ms) and timeout_ms in 1..60_000 do
    with {:ok, parameters} <- parameters(operation, parameters, state.generation),
         id = Integer.to_string(next_id),
         frame = %{
           "version" => 1,
           "id" => id,
           "operation" => Atom.to_string(operation),
           "parameters" => parameters,
           "timeout_ms" => timeout_ms
         },
         {:ok, encoded} <- Jason.encode(frame),
         line = encoded <> "\n",
         true <- byte_size(line) <= @maximum_line_bytes do
      next = if next_id == @maximum_counter, do: :exhausted, else: next_id + 1
      {:ok, id, line, %{state | next_id: next}}
    else
      _ -> :error
    end
  end

  def encode(%__MODULE__{next_id: :exhausted}, operation, _, _)
      when operation in @operations,
      do: :exhausted

  def encode(_, _, _, _), do: :error

  defp parameters(
         :open,
         %{host: host, port: port, generation: generation, security: %Security{} = security} =
           parameters,
         generation
       )
       when map_size(parameters) == 4 and is_integer(port) and port in 1..65_535 do
    with true <- numeric_host?(host),
         :ok <- Security.validate(security),
         :oscore <- security.mode do
      {:ok,
       %{
         "host" => host,
         "port" => port,
         "generation" => generation,
         "security" => %{
           "mode" => "oscore",
           "master_secret" => bytes(security.master_secret),
           "master_salt" => bytes(security.master_salt),
           "sender_id" => bytes(security.sender_id),
           "recipient_id" => bytes(security.recipient_id),
           "id_context" => optional_bytes(security.id_context),
           "context_store" => security.context_store
         }
       }}
    else
      _ -> :error
    end
  end

  defp parameters(
         :body_begin,
         %{body_id: body_id, length: length, sha256: hash} = parameters,
         _
       )
       when map_size(parameters) == 3 and is_integer(length) and length in 0..1_048_576 and
              is_binary(hash) and byte_size(hash) == 64 do
    if identifier?(body_id) and lowercase_hash?(hash),
      do: {:ok, %{"body_id" => body_id, "length" => length, "sha256" => hash}},
      else: :error
  end

  defp parameters(
         :body_chunk,
         %{body_id: body_id, offset: offset, data: data} = parameters,
         _
       )
       when map_size(parameters) == 3 and is_integer(offset) and offset in 0..1_048_576 and
              is_binary(data) and byte_size(data) <= 32_768 do
    if identifier?(body_id),
      do: {:ok, %{"body_id" => body_id, "offset" => offset, "data" => bytes(data)}},
      else: :error
  end

  defp parameters(:body_end, %{body_id: body_id} = parameters, _)
       when map_size(parameters) == 1 do
    if identifier?(body_id), do: {:ok, %{"body_id" => body_id}}, else: :error
  end

  defp parameters(
         :request,
         %{method: method, path: path, confirmable: confirmable} = parameters,
         _
       ) do
    with true <-
           Map.keys(parameters) --
             [:method, :path, :confirmable, :accept, :content_format, :body_id] == [],
         {:ok, wire_method} <- Map.fetch(@methods, method),
         true <- is_boolean(confirmable),
         :ok <- path(path, method, confirmable, parameters),
         :ok <- optional_format(parameters, :accept),
         :ok <- optional_format(parameters, :content_format),
         :ok <- optional_identifier(parameters, :body_id) do
      wire = %{
        "method" => wire_method,
        "path" => path,
        "confirmable" => confirmable
      }

      {:ok,
       wire
       |> optional_put("accept", Map.get(parameters, :accept))
       |> optional_put("content_format", Map.get(parameters, :content_format))
       |> optional_put("body_id", Map.get(parameters, :body_id))}
    else
      _ -> :error
    end
  end

  defp parameters(
         :observe,
         %{
           path: path,
           confirmable: confirmable,
           observation_kind: observation_kind,
           renew: renew
         } = parameters,
         _
       ) do
    with true <-
           Map.keys(parameters) -- [:path, :confirmable, :observation_kind, :renew, :accept] == [],
         true <- is_boolean(confirmable) and is_boolean(renew),
         true <- observation_kind in [:property, :event],
         :ok <- path(path, :get, confirmable, parameters),
         :ok <- optional_format(parameters, :accept) do
      wire = %{
        "path" => path,
        "confirmable" => confirmable,
        "observation_kind" => Atom.to_string(observation_kind),
        "renew" => renew
      }

      {:ok, optional_put(wire, "accept", Map.get(parameters, :accept))}
    else
      _ -> :error
    end
  end

  defp parameters(
         :credit,
         %{generation: generation, ack_seq: sequence} = parameters,
         generation
       )
       when map_size(parameters) == 2 and is_integer(sequence) and
              sequence in 0..@maximum_counter,
       do: {:ok, %{"generation" => generation, "ack_seq" => sequence}}

  defp parameters(
         :cancel,
         %{subscription_id: subscription_id, generation: generation} = parameters,
         generation
       )
       when map_size(parameters) == 2 do
    if identifier?(subscription_id),
      do: {:ok, %{"subscription_id" => subscription_id, "generation" => generation}},
      else: :error
  end

  defp parameters(:close, parameters, _) when parameters == %{}, do: {:ok, %{}}
  defp parameters(_, _, _), do: :error

  defp path(path, method, confirmable, parameters) do
    input = %{
      method: method,
      path: path,
      confirmable: confirmable,
      accept: Map.get(parameters, :accept),
      content_format: Map.get(parameters, :content_format)
    }

    case Wotex.CoAP.message(input) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp optional_format(parameters, key) do
    case Map.fetch(parameters, key) do
      :error -> :ok
      {:ok, nil} -> :ok
      {:ok, value} when is_integer(value) and value in 0..65_535 -> :ok
      _ -> :error
    end
  end

  defp optional_identifier(parameters, key) do
    case Map.fetch(parameters, key) do
      :error -> :ok
      {:ok, nil} -> :ok
      {:ok, value} -> if(identifier?(value), do: :ok, else: :error)
    end
  end

  defp optional_put(map, _, nil), do: map
  defp optional_put(map, key, value), do: Map.put(map, key, value)
  defp optional_bytes(nil), do: nil
  defp optional_bytes(value), do: bytes(value)
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp numeric_host?(host) when is_binary(host) and byte_size(host) in 1..45 do
    if String.valid?(host) and :binary.match(host, <<0>>) == :nomatch do
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp numeric_host?(_), do: false

  defp lowercase_hash?(hash) do
    Enum.all?(:binary.bin_to_list(hash), &(&1 in ?0..?9 or &1 in ?a..?f))
  end

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..64,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 in 0x20..0x7E))

  defp identifier?(_), do: false
end
