defmodule Wotex.Matter.Native.Wire do
  @moduledoc false

  alias Wotex.Matter.{Address, Error}

  @path_keys ~w(fabric_id node_id endpoint cluster member)

  @doc false
  @spec decode(atom(), term()) :: {:ok, term()} | {:error, Error.t()}
  def decode(:read, result), do: normalize(attribute(result))

  def decode(:read_paths, results), do: normalize(path_results(results, &attribute/1))
  def decode(:read_events, results), do: normalize(path_results(results, &event/1))

  def decode(:write, %{"path" => path, "status" => 0} = result) when map_size(result) == 2 do
    normalize(with {:ok, path} <- path(path), do: {:ok, %{path: path, status: 0}})
  end

  def decode(:invoke, %{"path" => path, "value" => value, "status" => 0} = result)
      when map_size(result) == 3 do
    normalize(
      with {:ok, path} <- optional(path, &path/1),
           {:ok, value} <- optional(value, &element/1) do
        {:ok, %{path: path, value: value, status: 0}}
      end
    )
  end

  def decode(_, _), do: {:error, Error.new(:invalid_frame)}

  @doc false
  @spec subscription(String.t(), term(), term()) ::
          {:ok, {:ok, term(), map()}} | {:error, Error.t()}
  def subscription("attribute", value, metadata) do
    with {:ok, value} <- element(value),
         {:ok, metadata} <- attribute_metadata(metadata) do
      {:ok, {:ok, value, metadata}}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  def subscription("event", value, metadata) do
    with {:ok, value} <- element(value),
         {:ok, metadata} <- event_metadata(metadata) do
      {:ok, {:ok, value, metadata}}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  def subscription(_, _, _), do: {:error, Error.new(:invalid_frame)}

  @doc false
  @spec error(term()) :: {:ok, Error.t()} | :error
  def error(%{"code" => code} = value) when map_size(value) in 1..4 and is_binary(code) do
    allowed = ["code", "effect", "status", "cluster_status"]

    with true <- Map.keys(value) -- allowed == [],
         {:ok, effect} <- effect(Map.get(value, "effect", "none")),
         {:ok, status} <- status(Map.get(value, "status")),
         {:ok, cluster_status} <- status(Map.get(value, "cluster_status")) do
      details =
        %{}
        |> optional_detail(:status, status)
        |> optional_detail(:cluster_status, cluster_status)

      {:ok, %{Error.new(error_code(code), nil, details) | effect: effect}}
    else
      _ -> :error
    end
  end

  def error(_), do: :error

  defp path_results(results, decoder) when is_list(results) and length(results) <= 1024 do
    traverse(results, fn
      %{"path" => raw_path, "result" => result} = entry when map_size(entry) == 2 ->
        with {:ok, path} <- path(raw_path),
             {:ok, result} <- path_result(result, decoder),
             true <- result_path?(result, path) do
          {:ok, %{path: path, result: result}}
        else
          _ -> :error
        end

      _ ->
        :error
    end)
  end

  defp path_results(_, _), do: {:error, Error.new(:invalid_frame)}

  defp path_result(%{"ok" => result} = value, decoder) when map_size(value) == 1 do
    case decoder.(result) do
      {:ok, decoded} -> {:ok, {:ok, decoded}}
      _ -> :error
    end
  end

  defp path_result(%{"error" => value} = result, _) when map_size(result) == 1 do
    case error(value) do
      {:ok, error} -> {:ok, {:error, error}}
      :error -> :error
    end
  end

  defp path_result(_, _), do: :error
  defp result_path?({:ok, %{path: actual}}, expected), do: actual == expected
  defp result_path?({:error, %Error{}}, _), do: true
  defp result_path?(_, _), do: false

  defp attribute(%{"path" => path, "value" => value, "data_version" => version} = report)
       when map_size(report) == 3 and
              (is_nil(version) or (is_integer(version) and version in 0..0xFFFFFFFF)) do
    with {:ok, path} <- path(path),
         {:ok, value} <- element(value) do
      {:ok, %{path: path, value: value, data_version: version}}
    end
  end

  defp attribute(_), do: :error

  defp event(
         %{
           "path" => path,
           "value" => value,
           "event_number" => number,
           "priority" => priority,
           "timestamp" => timestamp,
           "status" => 0
         } = event
       )
       when map_size(event) == 6 and is_integer(number) and number in 0..0xFFFFFFFFFFFFFFFF and
              is_integer(priority) and priority in 0..255 do
    with {:ok, path} <- path(path),
         {:ok, value} <- element(value),
         {:ok, timestamp} <- timestamp(timestamp) do
      {:ok,
       %{
         path: path,
         value: value,
         event_number: number,
         priority: priority,
         timestamp: timestamp,
         status: 0
       }}
    end
  end

  defp event(_), do: :error

  defp timestamp(%{"kind" => kind, "value" => value} = timestamp)
       when map_size(timestamp) == 2 and kind in ["epoch", "system"] and is_integer(value) and
              value in 0..0xFFFFFFFFFFFFFFFF,
       do: {:ok, %{kind: String.to_existing_atom(kind), value: value}}

  defp timestamp(_), do: :error

  defp attribute_metadata(
         %{
           "path" => raw_path,
           "data_version" => version,
           "initial" => initial,
           "report_id" => report_id,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = metadata
       )
       when map_size(metadata) == 7 and (is_nil(version) or is_integer(version)) and
              is_boolean(initial) and is_integer(report_id) and report_id > 0 and
              is_integer(minimum) and minimum in 0..65_535 and is_integer(maximum) and
              maximum in 1..65_535 and minimum <= maximum and is_integer(sdk_id) and
              sdk_id in 0..0xFFFFFFFF do
    with true <- is_nil(version) or version in 0..0xFFFFFFFF,
         {:ok, raw_path} <- path(raw_path),
         {:ok, path} <- Address.new(raw_path) do
      {:ok,
       %{
         kind: :attribute,
         path: path,
         data_version: version,
         initial: initial,
         report_id: report_id,
         min_interval_s: minimum,
         max_interval_s: maximum,
         sdk_subscription_id: sdk_id
       }}
    end
  end

  defp attribute_metadata(_), do: :error

  defp event_metadata(
         %{
           "path" => raw_path,
           "event_number" => number,
           "priority" => priority,
           "timestamp" => raw_timestamp,
           "initial" => initial,
           "report_id" => report_id,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = metadata
       )
       when map_size(metadata) == 9 and is_integer(number) and
              number in 0..0xFFFFFFFFFFFFFFFF and is_integer(priority) and priority in 0..255 and
              is_boolean(initial) and is_integer(report_id) and report_id > 0 and
              is_integer(minimum) and minimum in 0..65_535 and is_integer(maximum) and
              maximum in 1..65_535 and minimum <= maximum and is_integer(sdk_id) and
              sdk_id in 0..0xFFFFFFFF do
    with {:ok, raw_path} <- path(raw_path),
         {:ok, path} <- Address.new(raw_path),
         {:ok, timestamp} <- timestamp(raw_timestamp) do
      {:ok,
       %{
         kind: :event,
         path: path,
         event_number: number,
         priority: priority,
         timestamp: timestamp,
         initial: initial,
         report_id: report_id,
         min_interval_s: minimum,
         max_interval_s: maximum,
         sdk_subscription_id: sdk_id
       }}
    end
  end

  defp event_metadata(_), do: :error

  defp path(value) when is_map(value) and map_size(value) == 5 do
    if Enum.sort(Map.keys(value)) == Enum.sort(@path_keys) do
      {:ok,
       %{
         fabric_id: value["fabric_id"],
         node_id: value["node_id"],
         endpoint: value["endpoint"],
         cluster: value["cluster"],
         member: value["member"]
       }}
    else
      :error
    end
  end

  defp path(_), do: :error

  defp element(%{"tag" => tag, "type" => type, "value" => value} = element)
       when map_size(element) == 3 do
    with {:ok, tag} <- tag(tag),
         {:ok, type} <- type(type),
         {:ok, value} <- element_value(type, value) do
      {:ok, %{tag: tag, type: type, value: value}}
    end
  end

  defp element(_), do: :error
  defp tag("anonymous"), do: {:ok, :anonymous}
  defp tag(["context", id]) when is_integer(id) and id in 0..255, do: {:ok, {:context, id}}
  defp tag(_), do: :error

  defp type(type) when type in ~w(null i16 u8 u16 u32 boolean structure array),
    do: {:ok, String.to_existing_atom(type)}

  defp type(_), do: :error
  defp element_value(:null, nil), do: {:ok, nil}

  defp element_value(:i16, value) when is_integer(value) and value in -32_768..32_767,
    do: {:ok, value}

  defp element_value(:u8, value) when is_integer(value) and value in 0..0xFF, do: {:ok, value}
  defp element_value(:u16, value) when is_integer(value) and value in 0..0xFFFF, do: {:ok, value}

  defp element_value(:u32, value) when is_integer(value) and value in 0..0xFFFFFFFF,
    do: {:ok, value}

  defp element_value(:boolean, value) when is_boolean(value), do: {:ok, value}

  defp element_value(type, values) when type in [:structure, :array] and is_list(values) do
    traverse(values, &element/1)
  end

  defp element_value(_, _), do: :error

  defp traverse(values, function), do: traverse(values, function, [])
  defp traverse([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | rest], function, acc) do
    case function.(value) do
      {:ok, result} -> traverse(rest, function, [result | acc])
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp optional(nil, _), do: {:ok, nil}
  defp optional(value, function), do: function.(value)
  defp effect("none"), do: {:ok, :none}
  defp effect("unknown"), do: {:ok, :unknown}
  defp effect(_), do: :error
  defp status(nil), do: {:ok, nil}
  defp status(value) when is_integer(value) and value in 0..255, do: {:ok, value}
  defp status(_), do: :error
  defp optional_detail(details, _, nil), do: details
  defp optional_detail(details, key, value), do: Map.put(details, key, value)
  defp normalize({:ok, _} = result), do: result
  defp normalize({:error, %Error{}} = result), do: result
  defp normalize(_), do: {:error, Error.new(:invalid_frame)}

  defp error_code("authority_invalid"), do: :authority_invalid
  defp error_code("controller_already_open"), do: :controller_already_open
  defp error_code("controller_closed"), do: :controller_closed
  defp error_code("controller_start_failed"), do: :controller_start_failed
  defp error_code("controller_start_timeout"), do: :controller_start_timeout
  defp error_code("fabric_mismatch"), do: :fabric_mismatch
  defp error_code("interaction_busy"), do: :interaction_busy
  defp error_code("interaction_failed"), do: :interaction_failed
  defp error_code("interaction_no_response"), do: :interaction_no_response
  defp error_code("interaction_submit_failed"), do: :interaction_submit_failed
  defp error_code("interaction_status"), do: :interaction_status
  defp error_code("interaction_timeout"), do: :timeout
  defp error_code("interaction_unavailable"), do: :interaction_unavailable
  defp error_code("invalid_attribute_data"), do: :invalid_attribute_data
  defp error_code("invalid_backend_result"), do: :invalid_transport_return
  defp error_code("invalid_controller_identity"), do: :invalid_controller_identity
  defp error_code("invalid_event_data"), do: :invalid_event_data
  defp error_code("invalid_request"), do: :invalid_request
  defp error_code("invalid_response_path"), do: :invalid_response_path
  defp error_code("missing_path_result"), do: :missing_path_result
  defp error_code("not_supported"), do: :not_supported
  defp error_code("paa_trust_store_invalid"), do: :paa_trust_store_invalid
  defp error_code("response_limit"), do: :response_limit
  defp error_code("queue_overflow"), do: :queue_overflow
  defp error_code("receiver_closed"), do: :receiver_closed
  defp error_code("sdk_storage_failed"), do: :sdk_storage_failed
  defp error_code("session_establishment_failed"), do: :session_establishment_failed
  defp error_code("session_lost"), do: :session_lost
  defp error_code("storage_open_failed"), do: :storage_open_failed
  defp error_code("subscription_busy"), do: :busy
  defp error_code("subscription_cancel_timeout"), do: :timeout
  defp error_code("subscription_failed"), do: :subscription_failed
  defp error_code("subscription_submit_failed"), do: :subscription_submit_failed
  defp error_code("subscription_timeout"), do: :timeout
  defp error_code("subscription_unavailable"), do: :subscription_unavailable
  defp error_code("invalid_subscription"), do: :invalid_handle
  defp error_code("invalid_subscription_report"), do: :invalid_subscription_report
  defp error_code("invalid_subscription_result"), do: :invalid_subscription_result
  defp error_code("unsupported_schema"), do: :unsupported_schema
  defp error_code("unsupported_timestamp"), do: :unsupported_timestamp
  defp error_code(_), do: :native_error
end
