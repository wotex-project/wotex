defmodule Wotex.BACnet.Mapping do
  @moduledoc """
  Maps a W3C Web of Things Form to a native BACnet request value.

  `command/4` reads only the BACnet extension terms supported by the package's
  documented Form profile. It combines those terms with the selected WoT
  operation, optional input, and resolved href, then returns an immutable
  request map for `Wotex.BACnet.send/2` or a Property COV subscription. Unknown Form extension members
  remain owned by the original `Wotex.Form` value and are not reinterpreted.
  Known scalar type selectors are validated for every mapped operation. Explicit
  `contentType` selectors fail because this profile does not define a serializer.

  ## Semantics

  Mapping proves that a Form has the fields required for a supported protocol
  operation. It does not authorize that operation, establish peer reachability,
  or prove a physical effect. Invalid fields, unsupported operations, and
  inconsistent addressing return `Wotex.BACnet.Error` values without opening a
  connection or performing network I/O.
  """
  alias Wotex.BACnet.{Address, Error, Value}
  alias Wotex.Form

  @operations %{
    readproperty: :read_property,
    writeproperty: :write_property,
    observeproperty: :cov_property
  }

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    affordance = if operation == :invokeaction, do: :action, else: :property

    with {:ok, type} <- Map.fetch(@operations, operation),
         true <- Atom.to_string(operation) in Form.operations(form, for: affordance),
         :ok <- selectors(Form.to_map(form)),
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

  defp selectors(%{"contentType" => _}), do: {:error, Error.new(:unsupported_content_type)}
  defp selectors(%{"bacv:hasDataType" => type}), do: Value.validate_type(type)
  defp selectors(_), do: :ok

  defp uri(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{userinfo: nil, fragment: nil} = uri -> {:ok, uri}
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp uri(_), do: {:error, Error.new(:invalid_form_address)}

  defp target(%URI{scheme: "bacnet", host: device, port: nil, query: nil, path: path}, type, input) do
    with device_id when is_integer(device_id) <- number(device || ""),
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

      {:ok,
       %{target: Integer.to_string(device_id), message: subscription_identity(message, device_id)}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}

  defp subscription_identity(%{type: :cov_property} = message, device_id) do
    message
    |> Map.delete(:priority)
    |> Map.put(:device_instance, device_id)
  end

  defp subscription_identity(message, _), do: message
  defp property([]), do: {:ok, 85, nil}
  defp property([p]), do: {:ok, number(p), nil}
  defp property([p, i]), do: {:ok, number(p), number(i)}
  defp property(_), do: :error

  defp number(text) do
    if text != "" and unsigned_decimal?(text), do: String.to_integer(text), else: :invalid
  end

  defp unsigned_decimal?(<<>>), do: true
  defp unsigned_decimal?(<<digit, rest::binary>>) when digit in ?0..?9, do: unsigned_decimal?(rest)
  defp unsigned_decimal?(_), do: false

  defp input(message, type, value) when type in [:write, :write_property, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message

  defp convert(%{message: %{type: :write_property, value: value}} = mapping, form) do
    with {:ok, encoded} <- Value.encode(value, Map.get(form, "bacv:hasDataType")),
         :ok <- Value.validate_write(encoded),
         do: {:ok, put_in(mapping.message.value, encoded)}
  end

  defp convert(mapping, _), do: {:ok, mapping}
end
