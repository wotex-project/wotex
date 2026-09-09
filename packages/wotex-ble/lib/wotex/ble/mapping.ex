defmodule Wotex.BLE.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
  alias Wotex.BLE.{Address, Error, Value}
  alias Wotex.Form

  @operations %{
    readproperty: {:read, :property},
    writeproperty: {:write, :property},
    observeproperty: {:subscribe, :property},
    unobserveproperty: {:unsubscribe, :property},
    subscribeevent: {:subscribe, :event},
    unsubscribeevent: {:unsubscribe, :event}
  }
  @codecs Map.new(
            ~w(bytes utf8 boolean uint8 int8 uint16 int16 uint32 int32 uint64 int64 float32 float64)a,
            &{Atom.to_string(&1), &1}
          )
  @orders %{"little" => :little, "big" => :big}
  @modes %{"auto" => :auto, "notify" => :notify, "indicate" => :indicate}

  @doc "Maps a contextual Form to a typed native operation without acquiring a peer."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    with {:ok, {type, context}} <- operation(operation),
         {:ok, validated} <- validate_form(form, context),
         true <- Atom.to_string(operation) in Form.operations(validated, for: context),
         fields = Form.to_map(validated),
         :ok <- media(fields),
         :ok <- mode_applicability(fields, type),
         {:ok, value_type} <- selector(fields, "wotex:bleValueType", @codecs, :bytes),
         {:ok, byte_order} <- selector(fields, "wotex:bleByteOrder", @orders, :little),
         {:ok, mode} <- selector(fields, "wotex:bleMode", @modes, :auto),
         {:ok, target, address} <- target(href || Form.href(validated)),
         {:ok, message} <- message(address, type, input, value_type, byte_order) do
      {:ok,
       %{
         target: target,
         address: address,
         message: message,
         form: fields,
         value_type: value_type,
         byte_order: byte_order,
         mode: mode
       }}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:unsupported_operation)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_form)}
  end

  def command(_, _, _, _), do: {:error, Error.new(:invalid_form)}

  defp operation(operation) do
    case Map.fetch(@operations, operation) do
      {:ok, _} = result -> result
      :error -> {:error, Error.new(:unsupported_operation)}
    end
  end

  defp validate_form(form, context) do
    case Form.new(Form.to_map(form), for: context) do
      {:ok, _} = result -> result
      _ -> {:error, Error.new(:invalid_form)}
    end
  end

  defp media(fields) do
    if Map.has_key?(fields, "contentType"),
      do: {:error, Error.new(:unsupported_content_type)},
      else: :ok
  end

  defp mode_applicability(fields, type) when type in [:read, :write] do
    if Map.has_key?(fields, "wotex:bleMode"), do: {:error, Error.new(:invalid_selector)}, else: :ok
  end

  defp mode_applicability(_, _), do: :ok

  defp selector(fields, name, choices, default) do
    case Map.fetch(fields, name) do
      :error ->
        {:ok, default}

      {:ok, value} ->
        case Map.fetch(choices, value) do
          {:ok, _} = result -> result
          :error -> {:error, Error.new(:invalid_selector)}
        end
    end
  end

  defp target(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{
        scheme: "ble",
        host: device,
        port: nil,
        query: nil,
        userinfo: nil,
        fragment: nil,
        path: "/" <> topic
      }
      when is_binary(device) and byte_size(device) > 0 ->
        case Address.from_topic(topic) do
          {:ok, address} -> {:ok, device, address}
          _ -> {:error, Error.new(:invalid_form_address)}
        end

      _ ->
        {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_), do: {:error, Error.new(:invalid_form_address)}

  defp message(address, :write, input, type, order) do
    with {:ok, bytes} <- Value.encode(input, type, byte_order: order),
         do: {:ok, Map.merge(Map.from_struct(address), %{type: :write, value: bytes})}
  end

  defp message(address, type, _, _, _),
    do: {:ok, Map.put(Map.from_struct(address), :type, type)}
end
