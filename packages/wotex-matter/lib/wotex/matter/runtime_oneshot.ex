defmodule Wotex.Matter.RuntimeOneshot do
  @moduledoc false

  alias Wotex.Matter
  alias Wotex.Matter.{Address, Descriptor, Error, Session}
  alias Wotex.Runtime.{Request, Result}

  @doc false
  @spec preflight(atom(), Address.t(), term()) :: :ok | {:error, Error.t()}
  def preflight(:readproperty, address, _) do
    case Descriptor.lookup(:attribute, address, :read) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def preflight(operation, address, input) when operation in [:writeproperty, :invokeaction] do
    with {:ok, _} <- input(operation, address, input), do: :ok
  end

  def preflight(_, _, _), do: {:error, Error.new(:unsupported_operation)}

  @doc false
  @spec execute(Session.t(), map(), Request.t(), integer()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def execute(session, message, request, remaining) when remaining > 0 do
    with {:ok, address} <-
           message
           |> Map.take([:fabric_id, :node_id, :endpoint, :cluster, :member])
           |> Address.new(),
         {:ok, value} <- perform(%{session | timeout: remaining}, address, request) do
      Result.new(request.request_id, request.operation, value)
    end
  end

  def execute(_, _, _, _), do: {:error, Error.new(:deadline_exceeded)}

  defp perform(session, address, %Request{operation: :readproperty}) do
    with {:ok, report} <- Matter.read_attribute(session, address),
         do: Descriptor.from_element(:attribute, address, :read, report.value)
  end

  defp perform(session, address, %Request{operation: :writeproperty, input: value}) do
    with {:ok, element} <- input(:writeproperty, address, value),
         {:ok, %{status: 0}} <- Matter.write_attribute(session, address, element),
         do: {:ok, "written"}
  end

  defp perform(session, address, %Request{operation: :invokeaction, input: value}) do
    with {:ok, element} <- input(:invokeaction, address, value),
         {:ok, result} <- Matter.invoke_command(session, address, element) do
      response(result)
    end
  end

  defp input(operation, address, value) do
    {kind, verb} =
      case operation do
        :writeproperty -> {:attribute, :write}
        :invokeaction -> {:command, :invoke}
      end

    with {:ok, element} <- Descriptor.to_element(kind, address, verb, value),
         do: Descriptor.validate_element(kind, address, verb, element)
  end

  defp response(%{path: nil, value: nil, status: 0}), do: {:ok, nil}

  defp response(%{path: path, value: element, status: 0}),
    do: Descriptor.from_element(:command, path, :invoke, element)
end
