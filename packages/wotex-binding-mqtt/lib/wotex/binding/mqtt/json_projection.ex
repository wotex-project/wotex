defmodule Wotex.Binding.MQTT.JSONProjection do
  @moduledoc """
  Projects exact JSON fields from an explicitly matched MQTT delivery.

  `project/2` takes a `Wotex.Binding.MQTT.Delivery` and a closed selector map
  with exactly `"topic"` and `"path"`. An empty path selects the complete payload.
  Object segments are already decoded literal keys; list segments are canonical
  zero-based decimal indices such as `"0"`. Segments undergo no escape decoding
  or expression evaluation. Missing members, invalid indices and traversal
  through a scalar refuse; JSON null, false and empty text remain distinct values.

      iex> payload = ~s({"value":1.2300})
      iex> {:ok, delivery} = Wotex.Binding.MQTT.Delivery.new(payload, topic: "samples/value")
      iex> selector = %{"topic" => "samples/value", "path" => ["value"]}
      iex> {:ok, value, metadata} = Wotex.Binding.MQTT.JSONProjection.project(delivery, selector)
      iex> value
      %{"type" => "decimal", "coefficient" => "123", "exponent" => -2}
      iex> metadata
      %{topic: "samples/value", qos: 0, retained: false}

  `selector_schema/0` supplies structural profile validation. Use
  `validate_selector/1`, which returns `:ok` or an error tuple, for the MQTT
  Topic Name and UTF-8 byte constraints: 1 to 1,024 topic bytes and at most seven
  path segments of 0 to 128 bytes each. Wildcards are not Topic Names.

  Selector and delivery validation, including the 65,536-byte payload ceiling,
  precede Topic Name comparison. A different valid topic returns `:ignore`
  without JSON decoding. The complete matching payload passes
  `Wotex.Runtime.Codec.JSON.decode/1` before selection, so invalid unselected
  fields or exceeded tree/output limits still refuse. Numbers retain exact
  integers or normalized decimals without native floats; the canonical typed
  output must also fit 65,536 bytes.

  Success is `{:ok, value, metadata}`, preserving topic, QoS and retained status.
  Errors are sanitized `{:error, error}` tuples with a `Wotex.Binding.MQTT.Error`:

  | Code | Phase | Retry class |
  | --- | --- | --- |
  | `:invalid_profile_selector` | `:mapping` | `:permanent` |
  | `:invalid_delivery` | `:client` | `:protocol` |
  | `:profile_value_missing` | `:mapping` | `:protocol` |
  | `:json_invalid_input` | `:codec` | `:protocol` |
  | `:json_unsupported_value` | `:codec` | `:protocol` |
  | `:json_output_limit` | `:codec` | `:protocol` |

  This pure module starts no transport. The consumer owns source authentication,
  receipt clocks, continuity and freshness policy; a retained flag supplies no
  receipt time or freshness proof. Projection creates no registration or consumer
  authority.
  """

  alias Wotex.Binding.MQTT.{Delivery, Error, Topic}
  alias Wotex.Runtime.Codec.{JSON, Value}

  @doc "Returns the structural selector schema; semantic validation remains explicit."
  @spec selector_schema() :: map()
  def selector_schema do
    %{
      "type" => "object",
      "properties" => %{
        "topic" => %{"type" => "string", "minLength" => 1, "maxLength" => 1024},
        "path" => %{
          "type" => "array",
          "items" => %{"type" => "string", "minLength" => 0, "maxLength" => 128},
          "minItems" => 0,
          "maxItems" => 7
        }
      },
      "required" => ["path", "topic"],
      "additionalProperties" => false
    }
  end

  @doc "Checks the closed selector, exact MQTT Topic Name and UTF-8 byte ceilings."
  @spec validate_selector(term()) :: :ok | {:error, Error.t()}
  def validate_selector(%{"topic" => topic, "path" => path} = selector)
      when not is_struct(selector) and map_size(selector) == 2 do
    if text?(topic, 1, 1024) and Topic.validate_name(topic) == :ok and path?(path, 7),
      do: :ok,
      else: failure(:invalid_profile_selector)
  end

  def validate_selector(_), do: failure(:invalid_profile_selector)

  @doc "Selects one exact inert value and delivery metadata, or ignores another Topic Name."
  @spec project(term(), term()) ::
          {:ok, Value.t(), %{topic: String.t(), qos: 0..2, retained: boolean()}}
          | :ignore
          | {:error, Error.t()}
  def project(delivery, selector) do
    with :ok <- validate_selector(selector),
         :ok <- delivery(delivery),
         true <- Delivery.topic(delivery) == selector["topic"],
         {:ok, root} <- decode(Delivery.payload(delivery)),
         {:ok, value} <- select(root, selector["path"]) do
      {:ok, value,
       %{
         topic: Delivery.topic(delivery),
         qos: Delivery.qos(delivery),
         retained: Delivery.retained?(delivery)
       }}
    else
      false -> :ignore
      {:error, %Error{}} = error -> error
    end
  end

  defp path?([], _), do: true

  defp path?([segment | rest], left) when left > 0,
    do: text?(segment, 0, 128) and path?(rest, left - 1)

  defp path?(_, _), do: false

  defp text?(value, min, max),
    do: is_binary(value) and byte_size(value) in min..max and String.valid?(value)

  defp delivery(%Delivery{payload: payload, topic: topic, qos: qos, retain: retain} = value)
       when map_size(value) == 5 do
    case Delivery.new(payload, topic: topic, qos: qos, retain: retain) do
      {:ok, ^value} ->
        if byte_size(value.payload) <= 65_536, do: :ok, else: failure(:json_output_limit)

      _ ->
        failure(:invalid_delivery)
    end
  end

  defp delivery(_), do: failure(:invalid_delivery)

  defp decode(payload) do
    case JSON.decode(payload) do
      {:ok, value} -> {:ok, value}
      {:error, :invalid_input} -> failure(:json_invalid_input)
      {:error, :unsupported_value} -> failure(:json_unsupported_value)
      {:error, :output_limit} -> failure(:json_output_limit)
    end
  end

  defp select(value, []), do: {:ok, value}

  defp select(%{"type" => "object", "entries" => entries}, [key | rest]) do
    case Enum.find(entries, &(&1["key"] == key)) do
      nil -> failure(:profile_value_missing)
      entry -> select(entry["value"], rest)
    end
  end

  defp select(%{"type" => "list", "items" => items}, [key | rest]) do
    if byte_size(key) in 1..3 and Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, key) do
      case Enum.at(items, String.to_integer(key)) do
        nil -> failure(:profile_value_missing)
        value -> select(value, rest)
      end
    else
      failure(:profile_value_missing)
    end
  end

  defp select(_, _), do: failure(:profile_value_missing)

  defp failure(:invalid_profile_selector),
    do: error(:invalid_profile_selector, :mapping, :permanent, "invalid profile selector")

  defp failure(:invalid_delivery),
    do: error(:invalid_delivery, :client, :protocol, "invalid MQTT delivery")

  defp failure(:profile_value_missing),
    do: error(:profile_value_missing, :mapping, :protocol, "profile value is missing")

  defp failure(code), do: error(code, :codec, :protocol, "exact JSON projection refused")

  defp error(code, phase, class, message),
    do: {:error, Error.new(code, phase, class, message)}
end
