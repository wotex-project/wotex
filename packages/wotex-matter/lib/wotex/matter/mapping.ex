defmodule Wotex.Matter.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
  alias Wotex.Form
  alias Wotex.Matter.{Address, Error}
  @operations %{readproperty: :read, writeproperty: :write, invokeaction: :invoke}

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    affordance = if operation == :invokeaction, do: :action, else: :property

    with {:ok, type} <- Map.fetch(@operations, operation),
         true <- Atom.to_string(operation) in Form.operations(form, for: affordance),
         {:ok, uri} <- uri(href || Form.href(form)),
         {:ok, mapping} <- target(uri, type, input) do
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

  defp target(%URI{scheme: "matter", host: fabric, port: nil, query: nil, path: path}, type, input) do
    with [node, endpoint, cluster, member] <- String.split(path || "", "/", trim: true),
         {:ok, address} <-
           Address.new(%{
             fabric_id: number(fabric),
             node_id: number(node),
             endpoint: number(endpoint),
             cluster: number(cluster),
             member: number(member)
           }) do
      message =
        address
        |> Map.from_struct()
        |> Map.put(:type, type)
        |> input(type, input)

      {:ok, %{target: Integer.to_string(address.fabric_id), message: message}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}

  defp number(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> :invalid
    end
  end

  defp number(_), do: :invalid

  defp input(message, type, value) when type in [:write, :write_property, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message
end
