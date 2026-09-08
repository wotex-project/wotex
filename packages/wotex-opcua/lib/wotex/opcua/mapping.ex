defmodule Wotex.OPCUA.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
  alias Wotex.Form
  alias Wotex.OPCUA.{Address, Error, Value}
  @operations %{readproperty: :read, writeproperty: :write}

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
