defmodule Wotex.BLE.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
  alias Wotex.BLE.{Address, Error}
  alias Wotex.Form
  @operations %{readproperty: :read, writeproperty: :write}

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

  defp target(%URI{scheme: "ble", host: device, port: nil, query: nil, path: path}, type, input)
       when is_binary(device) and byte_size(device) > 0 do
    with [service, characteristic] <- String.split(path || "", "/", trim: true),
         {:ok, address} <- Address.new(%{service: service, characteristic: characteristic}) do
      message =
        address
        |> Map.from_struct()
        |> Map.put(:type, type)
        |> input(type, input)

      {:ok, %{target: device, message: message}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}

  defp input(message, type, value) when type in [:write, :write_property, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message
end
