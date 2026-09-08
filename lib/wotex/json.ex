defmodule Wotex.JSON do
  @moduledoc """
  Bounded JSON admission and deterministic encoding.

  `decode/2` rejects oversized, malformed, or hostile input before and during
  materialization: byte size and UTF-8 validity are checked first, nesting depth
  and string size are bounded by a lexical scan before allocation-heavy
  decoding, decoded strings are copied away from the source binary, and the
  decoded value is then checked for duplicate object members, collection size,
  node count, and depth.

  String size is measured on source bytes during the scan, so the decoded
  string is never larger than the limit. `validate/2` applies the same
  structural limits to a native JSON-compatible value that a consumer decoded
  elsewhere; there `:max_bytes` bounds the total string and key payload. `encode/2` produces the package
  canonical form with recursively sorted object keys. It is deterministic
  within Wotex and is not an RFC 8785 claim.
  """

  alias Wotex.Error
  alias Wotex.JSON.Limits

  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  @doc "Decodes JSON bytes into a JSON-compatible value under explicit limits."
  @spec decode(binary(), keyword()) :: {:ok, json_value()} | {:error, Error.t()}
  def decode(json, opts \\ [])

  def decode(json, opts) when is_binary(json) do
    with {:ok, limits} <- Limits.new(opts),
         :ok <- preflight(json, limits),
         {:ok, decoded} <- jason_decode(json),
         {:ok, normalized, _acc} <- normalize(decoded, initial_state(limits)) do
      {:ok, normalized}
    end
  end

  def decode(_json, _opts) do
    {:error, Error.new(:invalid_input, :parse, "JSON input must be binary")}
  end

  @doc "Validates native JSON-value semantics and configured resource limits."
  @spec validate(term(), keyword()) :: :ok | {:error, Error.t()}
  def validate(value, opts \\ []) do
    with {:ok, limits} <- Limits.new(opts),
         {:ok, _acc} <- walk(value, initial_state(limits)) do
      :ok
    end
  end

  @doc "Encodes a valid JSON value with recursively sorted object keys."
  @spec encode(json_value(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, opts \\ []) do
    with :ok <- validate(value, opts) do
      {:ok, IO.iodata_to_binary(encode_value(value))}
    end
  end

  @doc "Escapes one RFC 6901 JSON Pointer path segment."
  @spec pointer_segment(String.t()) :: String.t()
  def pointer_segment(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

  @doc "Appends one member name to a JSON Pointer, escaping it as RFC 6901 requires."
  @spec join_pointer(String.t(), String.t()) :: String.t()
  def join_pointer(pointer, member), do: join(pointer, member)

  @doc "Resolves an RFC 6901 JSON Pointer against a JSON-compatible value."
  @spec resolve_pointer(json_value(), String.t()) :: {:ok, json_value()} | :error
  def resolve_pointer(value, ""), do: {:ok, value}

  def resolve_pointer(value, "/" <> pointer) do
    pointer
    |> String.split("/")
    |> Enum.map(&unescape_segment/1)
    |> Enum.reduce_while({:ok, value}, fn segment, {:ok, current} ->
      case step(current, segment) do
        {:ok, next} -> {:cont, {:ok, next}}
        :error -> {:halt, :error}
      end
    end)
  end

  def resolve_pointer(_value, _pointer), do: :error

  defp step(current, segment) when is_map(current), do: Map.fetch(current, segment)

  defp step(current, segment) when is_list(current) do
    case Integer.parse(segment) do
      {index, ""} when index >= 0 and index < length(current) -> {:ok, Enum.at(current, index)}
      _other -> :error
    end
  end

  defp step(_current, _segment), do: :error

  defp unescape_segment(segment) do
    segment
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end

  defp initial_state(%Limits{} = limits) do
    %{limits: limits, depth: 0, nodes: 0, bytes: 0, path: "/"}
  end

  defp preflight(json, %Limits{} = limits) do
    cond do
      byte_size(json) > limits.max_bytes ->
        {:error,
         Error.new(:byte_limit_exceeded, :parse, "JSON exceeds the configured byte limit", "/", %{
           bytes: byte_size(json),
           max_bytes: limits.max_bytes
         })}

      not String.valid?(json) ->
        {:error, Error.new(:invalid_string, :parse, "JSON source must be valid UTF-8", "/")}

      true ->
        scan(json, 0, limits)
    end
  end

  defp scan(<<>>, _depth, _limits), do: :ok

  defp scan(<<?", rest::binary>>, depth, limits), do: scan_string(rest, 0, depth, limits)

  defp scan(<<byte, rest::binary>>, depth, limits) when byte in [?{, ?[] do
    if depth + 1 > limits.max_depth do
      {:error,
       Error.new(:depth_limit_exceeded, :parse, "JSON exceeds the configured nesting depth", "/", %{
         max_depth: limits.max_depth
       })}
    else
      scan(rest, depth + 1, limits)
    end
  end

  defp scan(<<byte, rest::binary>>, depth, limits) when byte in [?}, ?]] do
    scan(rest, max(depth - 1, 0), limits)
  end

  defp scan(<<_byte, rest::binary>>, depth, limits), do: scan(rest, depth, limits)

  defp scan_string(<<?\\, _escaped, rest::binary>>, size, depth, limits) do
    scan_string(rest, size + 2, depth, limits)
  end

  defp scan_string(<<?", rest::binary>>, _size, depth, limits), do: scan(rest, depth, limits)
  defp scan_string(<<>>, _size, _depth, _limits), do: :ok

  defp scan_string(<<_byte, rest::binary>>, size, depth, limits) do
    if size + 1 > limits.max_string_bytes do
      {:error,
       Error.new(
         :string_limit_exceeded,
         :parse,
         "JSON string exceeds the configured byte limit",
         "/",
         %{
           max_string_bytes: limits.max_string_bytes
         }
       )}
    else
      scan_string(rest, size + 1, depth, limits)
    end
  end

  defp jason_decode(json) do
    case Jason.decode(json, objects: :ordered_objects, strings: :copy) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error,
         Error.new(:invalid_json, :parse, "JSON could not be decoded", "/", %{
           reason: Exception.message(reason)
         })}
    end
  end

  defp normalize(_value, %{nodes: nodes, limits: %{max_nodes: max_nodes}, path: path})
       when nodes >= max_nodes do
    {:error, node_limit(path, max_nodes)}
  end

  defp normalize(%Jason.OrderedObject{values: pairs}, state) do
    with :ok <- check_collection(length(pairs), state) do
      Enum.reduce_while(pairs, {:ok, %{}, count_node(state)}, &normalize_member(&1, &2, state))
    end
  end

  defp normalize(values, state) when is_list(values) do
    with :ok <- check_collection(length(values), state),
         {:ok, reversed, next_state} <-
           values
           |> Stream.with_index()
           |> Enum.reduce_while({:ok, [], count_node(state)}, &normalize_item(&1, &2, state)) do
      {:ok, Enum.reverse(reversed), next_state}
    end
  end

  defp normalize(value, state), do: {:ok, value, count_node(state)}

  defp normalize_member({key, child}, {:ok, acc, acc_state}, parent) do
    if Map.has_key?(acc, key) do
      {:halt,
       {:error,
        Error.new(
          :duplicate_member,
          :parse,
          "JSON object member is duplicated",
          join(parent.path, key)
        )}}
    else
      case normalize(child, child_state(parent, acc_state, key)) do
        {:ok, normalized, next_state} -> {:cont, {:ok, Map.put(acc, key, normalized), next_state}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end
  end

  defp normalize_item({child, index}, {:ok, acc, acc_state}, parent) do
    case normalize(child, child_state(parent, acc_state, index)) do
      {:ok, normalized, next_state} -> {:cont, {:ok, [normalized | acc], next_state}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp walk(_value, %{nodes: nodes, limits: %{max_nodes: max_nodes}, path: path})
       when nodes >= max_nodes do
    {:error, node_limit(path, max_nodes)}
  end

  defp walk(_value, %{depth: depth, limits: %{max_depth: max_depth}, path: path})
       when depth > max_depth do
    {:error, depth_limit(path, max_depth)}
  end

  defp walk(value, state) when is_nil(value) or is_boolean(value) or is_number(value) do
    {:ok, count_node(state)}
  end

  defp walk(value, state) when is_binary(value) do
    with :ok <- validate_string(value, state) do
      count_bytes(count_node(state), byte_size(value))
    end
  end

  defp walk(values, state) when is_list(values) do
    walk_list(values, count_node(state), state, 0)
  end

  defp walk(value, state) when is_map(value) and not is_struct(value) do
    with :ok <- check_collection(map_size(value), state) do
      Enum.reduce_while(value, {:ok, count_node(state)}, &walk_member(&1, &2, state))
    end
  end

  defp walk(_value, %{path: path}) do
    {:error, Error.new(:invalid_json_value, :value, "Value cannot be represented in JSON", path)}
  end

  defp walk_list([], acc_state, _parent, _index), do: {:ok, acc_state}

  defp walk_list([value | rest], acc_state, parent, index) do
    with :ok <- check_collection(index + 1, parent),
         {:ok, next_state} <- walk(value, child_state(parent, acc_state, index)) do
      walk_list(rest, next_state, parent, index + 1)
    end
  end

  defp walk_list(_tail, _acc_state, parent, _index) do
    {:error,
     Error.new(:invalid_json_value, :value, "JSON arrays must be proper lists", parent.path)}
  end

  defp walk_member({key, child}, {:ok, acc_state}, parent) when is_binary(key) do
    with :ok <- validate_string(key, parent),
         {:ok, keyed_state} <- count_bytes(acc_state, byte_size(key)),
         {:ok, next_state} <- walk(child, child_state(parent, keyed_state, key)) do
      {:cont, {:ok, next_state}}
    else
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp walk_member({key, _child}, _acc, parent) do
    {:halt,
     {:error,
      Error.new(:non_string_key, :value, "JSON object keys must be strings", parent.path, %{
        key: inspect(key, limit: 10, printable_limit: 40)
      })}}
  end

  defp check_collection(size, %{limits: %{max_collection_size: max}, path: path})
       when size > max do
    {:error,
     Error.new(
       :collection_limit_exceeded,
       :value,
       "JSON container exceeds the configured member limit",
       path,
       %{max_collection_size: max}
     )}
  end

  defp check_collection(_size, _state), do: :ok

  defp count_node(state), do: %{state | nodes: state.nodes + 1}

  defp count_bytes(%{bytes: bytes, limits: %{max_bytes: max_bytes}, path: path} = state, size) do
    if bytes + size > max_bytes do
      {:error,
       Error.new(
         :byte_limit_exceeded,
         :value,
         "JSON string payload exceeds the configured byte limit",
         path,
         %{
           max_bytes: max_bytes
         }
       )}
    else
      {:ok, %{state | bytes: bytes + size}}
    end
  end

  defp validate_string(value, state) do
    cond do
      not String.valid?(value) ->
        {:error,
         Error.new(:invalid_string, :value, "JSON strings must contain valid UTF-8", state.path)}

      byte_size(value) > state.limits.max_string_bytes ->
        {:error, string_limit(state.path, state.limits.max_string_bytes)}

      true ->
        :ok
    end
  end

  defp node_limit(path, max_nodes) do
    Error.new(:node_limit_exceeded, :value, "JSON value exceeds the configured node limit", path, %{
      max_nodes: max_nodes
    })
  end

  defp depth_limit(path, max_depth) do
    Error.new(
      :depth_limit_exceeded,
      :value,
      "JSON value exceeds the configured nesting depth",
      path,
      %{
        max_depth: max_depth
      }
    )
  end

  defp string_limit(path, max_string_bytes) do
    Error.new(
      :string_limit_exceeded,
      :value,
      "JSON string exceeds the configured byte limit",
      path,
      %{
        max_string_bytes: max_string_bytes
      }
    )
  end

  defp encode_value(value) when is_map(value) do
    encoded_entries =
      value
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, child} ->
        [Jason.encode_to_iodata!(key), ?:, encode_value(child)]
      end)

    [?{, Enum.intersperse(encoded_entries, ?,), ?}]
  end

  defp encode_value(value) when is_list(value) do
    encoded_entries = Enum.map(value, &encode_value/1)

    [?[, Enum.intersperse(encoded_entries, ?,), ?]]
  end

  defp encode_value(value), do: Jason.encode_to_iodata!(value)

  defp child_state(parent, acc_state, segment) do
    %{acc_state | depth: parent.depth + 1, path: join(parent.path, segment)}
  end

  defp join("/", segment), do: "/" <> pointer_segment(to_string(segment))
  defp join(path, segment), do: path <> "/" <> pointer_segment(to_string(segment))
end
