defmodule Wotex.BACnet.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
  alias Wotex.BACnet.{Address, Error, Value}
  alias Wotex.Form
  @operations %{readproperty: :read_property, writeproperty: :write_property}

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    affordance = if operation == :invokeaction, do: :action, else: :property

    with {:ok, type} <- Map.fetch(@operations, operation),
         true <- Atom.to_string(operation) in Form.operations(form, for: affordance),
         {:ok, uri} <- uri(href || Form.href(form)),
         {:ok, mapping} <- target(uri, type, input),
         {:ok, mapping} <- convert(mapping, Form.to_map(form)) do
      {:ok, Map.put(mapping, :form, Form.to_map(form))}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:unsupported_operation)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_form_address)}
  end

  def command(_, _, _, _), do: {:error, Error.new(:invalid_form)}

  defp uri(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{userinfo: nil, fragment: nil} = uri -> {:ok, uri}
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp uri(_), do: {:error, Error.new(:invalid_form_address)}

  defp target(%URI{scheme: "bacnet", host: device, port: nil, query: nil, path: path}, type, input) do
    with {device_id, ""} <- Integer.parse(device || ""),
         true <- device_id in 0..4_194_302,
         [object | rest] <- String.split(path || "", "/", trim: true),
         [object_type, instance] <- String.split(object, ","),
         {:ok, property, index} <- property(rest),
         {:ok, address} <-
           Address.new(%{
             object_type: number(object_type),
             instance: number(instance),
             property: property,
             array_index: index
           }) do
      message =
        address
        |> Map.from_struct()
        |> Map.put(:type, type)
        |> input(type, input)

      {:ok, %{target: Integer.to_string(device_id), message: message}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}
  defp property([]), do: {:ok, 85, nil}
  defp property([p]), do: {:ok, number(p), nil}
  defp property([p, i]), do: {:ok, number(p), number(i)}
  defp property(_), do: :error

  defp number(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> :invalid
    end
  end

  defp input(message, type, value) when type in [:write, :write_property, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message

  defp convert(%{message: %{type: :write_property, value: value}} = mapping, form) do
    with {:ok, encoded} <- Value.encode(value, Map.get(form, "bacv:hasDataType")),
         do: {:ok, put_in(mapping.message.value, encoded)}
  end

  defp convert(mapping, _), do: {:ok, mapping}
end
