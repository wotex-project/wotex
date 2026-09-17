defmodule Wotex.OPCUA.Mapping do
  @moduledoc """
  Maps a W3C Web of Things Form to a concrete OPC UA request.

  `command/4` accepts Property reads, writes and observation start/stop
  operations declared by the Form; observation maps to an `:observe` message
  that only a streaming transport path uses. It parses
  an `opc.tcp` href, requires exactly one NodeId in the `id` query parameter,
  supplies the default port 4840, and constructs an immutable request map. A
  write value is converted through `Wotex.OPCUA.Value` when the Form declares
  `wotex:variantType`, or when the supplied value already carries its type. The original Form map is retained
  with unknown extension terms.

  Mapping is pure and opens no secure channel. It rejects malformed endpoints,
  user information, fragments, invalid NodeIds, missing type information, and
  unsupported operations. A Form that supplies `contentType` returns
  `unsupported_content_type`: the binding profiles declare no media type and the
  native protocol values are not a serialized content format.
  Success does not authorize service access, prove that
  the node exists, or establish canonical Property state.
  """
  alias Wotex.Form
  alias Wotex.OPCUA.{Address, Error, Value}

  @operations %{
    readproperty: :read,
    writeproperty: :write,
    observeproperty: :observe,
    unobserveproperty: :observe
  }

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    affordance = if operation == :invokeaction, do: :action, else: :property

    with :ok <- media(Form.to_map(form)),
         {:ok, type} <- Map.fetch(@operations, operation),
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

  defp media(%{"contentType" => _}), do: {:error, Error.new(:unsupported_content_type)}
  defp media(_), do: :ok

  defp uri(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{userinfo: nil, fragment: nil} = uri -> {:ok, uri}
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp uri(_), do: {:error, Error.new(:invalid_form_address)}

  defp target(%URI{scheme: "opc.tcp", host: host, port: port, query: query} = uri, type, input)
       when is_binary(host) and byte_size(host) > 0 do
    with true <- is_nil(port) or port in 1..65_535,
         [{"id", node_id}] <- URI.query_decoder(query || "") |> Enum.to_list(),
         {:ok, address} <- Address.new(node_id) do
      endpoint = URI.to_string(%{uri | query: nil, port: port || 4840})
      {:ok, %{target: endpoint, message: input(%{type: type, node_id: address}, type, input)}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}

  defp input(message, type, value) when type in [:write, :write_property, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message

  defp convert(%{message: %{type: :write, value: value}} = mapping, form) do
    with {:ok, encoded} <- Value.encode(value, Map.get(form, "wotex:variantType")),
         do: {:ok, put_in(mapping.message.value, encoded)}
  end

  defp convert(mapping, _), do: {:ok, mapping}
end
