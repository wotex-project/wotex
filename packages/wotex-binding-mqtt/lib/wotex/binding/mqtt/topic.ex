defmodule Wotex.Binding.MQTT.Topic do
  @moduledoc """
  MQTT Topic Name and Topic Filter validation.

  Topic Names reject wildcards. Topic Filters accept `+` only as a complete
  level and `#` only as the final complete level.
  """

  alias Wotex.Binding.MQTT.Error

  @max_bytes 65_535

  @doc "Validates an MQTT Topic Name."
  @spec validate_name(term()) :: :ok | {:error, Error.t()}
  def validate_name(name) do
    with :ok <- validate_common(name, :invalid_topic_name, "Topic Name"),
         false <- String.contains?(name, ["+", "#"]) do
      :ok
    else
      true ->
        {:error,
         Error.new(
           :topic_name_contains_wildcard,
           :topic,
           "Topic Name must not contain wildcard characters"
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @doc "Validates an MQTT Topic Filter, including MQTT 5 shared syntax."
  @spec validate_filter(term()) :: :ok | {:error, Error.t()}
  def validate_filter(filter) do
    with :ok <- validate_common(filter, :invalid_topic_filter, "Topic Filter"),
         :ok <- validate_shared_prefix(filter),
         true <- valid_filter_levels?(effective_filter(filter)) do
      :ok
    else
      false ->
        {:error,
         Error.new(
           :invalid_topic_filter_wildcard,
           :topic,
           "Topic Filter contains a malformed wildcard"
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @doc "Normalizes one Topic Filter or a non-empty list of Topic Filters."
  @spec normalize_filters(term()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def normalize_filters(filter) when is_binary(filter), do: normalize_filters([filter])

  def normalize_filters(filters) when is_list(filters) and filters != [] do
    Enum.reduce_while(filters, {:ok, []}, fn filter, {:ok, valid} ->
      case validate_filter(filter) do
        :ok -> {:cont, {:ok, [filter | valid]}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, valid} -> {:ok, Enum.reverse(valid)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def normalize_filters(_filters) do
    {:error,
     Error.new(
       :invalid_topic_filters,
       :topic,
       "mqv:filter must be a Topic Filter or a non-empty list of Topic Filters"
     )}
  end

  @doc "Returns whether a valid Topic Filter matches a valid Topic Name."
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(filter, name) do
    with :ok <- validate_filter(filter),
         :ok <- validate_name(name) do
      effective = effective_filter(filter)

      not (String.starts_with?(effective, ["#", "+"]) and String.starts_with?(name, "$")) and
        match_levels(
          String.split(effective, "/", trim: false),
          String.split(name, "/", trim: false)
        )
    else
      _invalid -> false
    end
  end

  defp validate_common(value, code, label) when is_binary(value) do
    cond do
      value == "" ->
        {:error, Error.new(code, :topic, "#{label} must contain at least one character")}

      not String.valid?(value) ->
        {:error, Error.new(code, :topic, "#{label} must be valid UTF-8")}

      byte_size(value) > @max_bytes ->
        {:error,
         Error.new(code, :topic, "#{label} exceeds the MQTT UTF-8 encoded string limit", %{
           max_bytes: @max_bytes
         })}

      String.contains?(value, <<0>>) ->
        {:error, Error.new(code, :topic, "#{label} must not contain the null character")}

      true ->
        :ok
    end
  end

  defp validate_common(_value, code, label),
    do: {:error, Error.new(code, :topic, "#{label} must be a string")}

  defp validate_shared_prefix("$share/" <> remainder) do
    case String.split(remainder, "/", parts: 2) do
      [group, filter]
      when group != "" and filter != "" ->
        if String.contains?(group, ["+", "#"]) do
          invalid_shared_filter()
        else
          :ok
        end

      _invalid ->
        invalid_shared_filter()
    end
  end

  defp validate_shared_prefix(_filter), do: :ok

  defp invalid_shared_filter do
    {:error,
     Error.new(
       :invalid_shared_topic_filter,
       :topic,
       "shared Topic Filter must contain a group and a Topic Filter"
     )}
  end

  defp effective_filter("$share/" <> remainder) do
    [_group, filter] = String.split(remainder, "/", parts: 2)
    filter
  end

  defp effective_filter(filter), do: filter

  defp valid_filter_levels?(filter) do
    levels = String.split(filter, "/", trim: false)
    last_index = length(levels) - 1

    levels
    |> Enum.with_index()
    |> Enum.all?(fn
      {"#", index} -> index == last_index
      {"+", _index} -> true
      {level, _index} -> not String.contains?(level, ["+", "#"])
    end)
  end

  defp match_levels(["#"], _names), do: true
  defp match_levels([], []), do: true
  defp match_levels([], _names), do: false
  defp match_levels(_filters, []), do: false

  defp match_levels(["+" | filters], [_name | names]),
    do: match_levels(filters, names)

  defp match_levels([level | filters], [level | names]), do: match_levels(filters, names)

  defp match_levels(_filters, _names), do: false
end
